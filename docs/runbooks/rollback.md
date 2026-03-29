# Rollback Runbook — voidnxlabs Stack

**Audience**: On-call engineers
**Scope**: All production services in the voidnxlabs Sovereign Intelligence Platform
**Last updated**: 2026-03-29

---

## Decision Tree

```
Incident triggered
      │
      ▼
Is the system fully down?
  ├── YES → Go to §1 (Emergency Recovery)
  └── NO  → Which service is degraded?
               ├── Phantom / Cerebro / SecureLLM-Bridge → §2 (Docker Rollback)
               ├── NATS / JetStream → §3 (NATS Recovery)
               ├── Database (PostgreSQL) → §4 (Database Restore)
               ├── NixOS system → §5 (NixOS Rollback)
               ├── SOPS / secrets → §6 (Secrets Rotation)
               └── LLM providers failing → §7 (Provider Failover)
```

---

## §1 — Emergency Recovery (Full Stack Down)

```bash
# 1. Stop everything cleanly
cd ~/master
docker compose --profile full down

# 2. Check for corrupt volumes
docker volume ls
docker system df

# 3. Restore from last known-good state
# See §4 for database restore, §3 for NATS

# 4. Bring up core services only
docker compose --profile core up -d

# 5. Verify health
./sentinel/scripts/smoke-test.sh

# 6. Bring up intelligence tier only after core is green
docker compose --profile intelligence up -d
```

**Escalation**: If core services fail to start after restore, check:
- Docker daemon health: `systemctl status docker`
- Disk space: `df -h` — NATS JetStream needs space in `/data`
- Network conflicts: `docker network ls` — remove stale `spectre-net` if needed

---

## §2 — Docker Compose Service Rollback

### Identify the last working image tag

```bash
# List recent tags for a service
docker images ghcr.io/voidnxsec/phantom-api --format "table {{.Tag}}\t{{.CreatedAt}}" | head -10
docker images ghcr.io/voidnxsec/cerebro --format "table {{.Tag}}\t{{.CreatedAt}}" | head -10
docker images ghcr.io/voidnxsec/securellm-bridge --format "table {{.Tag}}\t{{.CreatedAt}}" | head -10
```

### Pin to a specific tag

```bash
# In docker-compose.yml, override the image tag:
#   image: ghcr.io/voidnxsec/phantom-api:v1.2.3

# Or via env override:
PHANTOM_IMAGE_TAG=v1.2.3 docker compose up -d phantom-api
```

### Rolling back a single service

```bash
# Stop the bad container
docker compose stop phantom-api

# Pull the known-good image
docker pull ghcr.io/voidnxsec/phantom-api:v1.2.3

# Start with pinned tag
PHANTOM_IMAGE_TAG=v1.2.3 docker compose up -d phantom-api

# Verify
curl -s localhost:8008/health | jq .
```

### Verifying the rollback

```bash
# Run smoke tests
cd sentinel && poetry run pytest scenarios/ -m e2e -v --timeout=30

# Check service logs for errors
docker compose logs --tail=50 phantom-api
docker compose logs --tail=50 cerebro
docker compose logs --tail=50 securellm-bridge
```

---

## §3 — NATS / JetStream Recovery

### NATS server restart (non-destructive)

```bash
docker compose restart nats

# Wait for JetStream to recover
sleep 5
nats --server nats://localhost:4222 server ping
nats --server nats://localhost:4222 account info
```

### Stream missing or corrupt

```bash
# List current streams
nats --server nats://localhost:4222 stream list

# Re-initialize missing streams (idempotent)
cd sentinel
./scripts/init-jetstream.sh

# Verify streams
nats --server nats://localhost:4222 stream info INGEST
nats --server nats://localhost:4222 stream info COGNITION
nats --server nats://localhost:4222 stream info LLM
```

### Replay missed events from JetStream

```bash
# Create a durable consumer to replay all events from a stream
nats --server nats://localhost:4222 consumer add INGEST replay-consumer \
    --filter "ingest.>" \
    --deliver all \
    --ack explicit \
    --pull

# Pull and inspect
nats --server nats://localhost:4222 consumer next INGEST replay-consumer
```

### JetStream store corruption

```bash
# Stop NATS
docker compose stop nats

# Backup corrupt store (for forensics)
cp -r ./spectre/data/nats ./spectre/data/nats.bak.$(date +%Y%m%d_%H%M%S)

# Clear store and restart (loses all buffered events)
rm -rf ./spectre/data/nats
docker compose up -d nats

# Re-initialize streams
sleep 5
./sentinel/scripts/init-jetstream.sh
```

> ⚠️ Clearing the JetStream store loses all buffered/undelivered events.
> Services will miss events published during the outage window.
> Phantom and Cerebro are designed to tolerate this — pipeline state is in PostgreSQL/ChromaDB.

---

## §4 — Database Restore (PostgreSQL / TimescaleDB)

### List available backups

```bash
ls -lh /var/lib/voidnxlabs/backups/postgres/daily/ | tail -10
ls -lh /var/lib/voidnxlabs/backups/postgres/weekly/
```

### Point-in-time restore (to most recent backup)

```bash
# Identify the latest daily backup
BACKUP=$(ls -t /var/lib/voidnxlabs/backups/postgres/daily/neotron_daily_*.sql.gz | head -1)
echo "Restoring from: $BACKUP"

# Perform restore (will drop + recreate neotron DB)
./sentinel/scripts/restore-postgres.sh "$BACKUP"
```

### Restore to a specific date

```bash
# Find backup closest to the incident time
ls /var/lib/voidnxlabs/backups/postgres/daily/neotron_daily_20260329_*.sql.gz

# Restore
./sentinel/scripts/restore-postgres.sh \
    /var/lib/voidnxlabs/backups/postgres/daily/neotron_daily_20260329_020000.sql.gz
```

### Verify after restore

```bash
psql -h localhost -U postgres -d neotron -c "\dt"
psql -h localhost -U postgres -d neotron -c "SELECT count(*) FROM audit_logs;"

# Run compliance suite
cd sentinel && poetry run pytest scenarios/ -m compliance -v
```

### Manual backup before risky operations

```bash
FORCE=yes ./sentinel/scripts/backup-postgres.sh
```

---

## §5 — NixOS System Rollback

### List available system generations

```bash
nixos-rebuild list-generations
# Or:
nix-env --list-generations --profile /nix/var/nix/profiles/system
```

### Roll back to previous generation

```bash
# Immediate rollback (takes effect now, without reboot)
nixos-rebuild switch --rollback

# Or target a specific generation
nix-env --switch-generation 42 --profile /nix/var/nix/profiles/system
nixos-rebuild switch
```

### Roll back via bootloader (after bad boot)

At boot, select the previous generation from the systemd-boot or GRUB menu.
Generations are listed newest-first.

### Verify after NixOS rollback

```bash
# Check service status
systemctl status phantom-api owasaka ai-agent-os

# Check current generation
nixos-rebuild list-generations | tail -3

# Verify firewall (should NOT expose internal ports)
nft list ruleset | grep -E "4222|8222|8080"
# Expected: no matches (internal ports must not be exposed)
```

---

## §6 — SOPS Secrets / NKey Rotation

### Rotate a single NKey

```bash
cd spectre/config/nkeys

# Generate new key
nix run nixpkgs#nkeys -- -gen user > phantom.nk.new

# Encrypt with SOPS
sops -e phantom.nk.new > phantom.nk.enc.new

# Update nats-server.conf with new public key
NEW_PUBKEY=$(nix run nixpkgs#nkeys -- -pub < phantom.nk.new)
sed -i "s/UATKNNRUFX3CAHNS4L23BCP2MLBPWB6L7U2RSAYGUF3TXKVFCZVOGRQ6/$NEW_PUBKEY/" \
    spectre/config/nats-server.conf

# Rotate files
mv phantom.nk phantom.nk.bak
mv phantom.nk.new phantom.nk
mv phantom.nk.enc phantom.nk.enc.bak
mv phantom.nk.enc.new phantom.nk.enc

# Restart NATS to load new config
docker compose restart nats

# Restart affected service with new seed
PHANTOM_NKEY_SEED=$(cat phantom.nk) docker compose up -d phantom-api
```

> See `sentinel/scripts/rotate-nkeys.sh` for the full automated rotation.

### Rotate TLS certificates

```bash
# See sentinel/scripts/rotate-tls.sh
./sentinel/scripts/rotate-tls.sh
```

### Emergency key revocation

```bash
# If a key is compromised:
# 1. Remove the affected nkey from nats-server.conf authorization block
# 2. Restart NATS immediately
docker compose restart nats

# 3. The compromised service will be locked out immediately
# 4. Generate and deploy a new key (see rotation above)
# 5. Audit NATS logs for unauthorized publishes during the exposure window
docker compose logs nats | grep "Authorization Violation"
```

---

## §7 — LLM Provider Failover

### Check provider health via SecureLLM Bridge

```bash
curl -s localhost:8081/api/providers | jq .
curl -s localhost:8081/api/health | jq .
```

### Manual provider override

The bridge uses circuit breakers. If a provider is tripping, force-route to another:

```bash
# Check circuit breaker state in logs
docker compose logs securellm-bridge | grep "Circuit breaker"

# Use provider-specific model prefix in requests:
# "model": "deepseek/deepseek-chat"    → force DeepSeek
# "model": "groq/llama-3.3-70b"        → force Groq
# "model": "ml-ops/local-model"         → force local GPU inference
# "model": "llamacpp/local-model"       → force llama.cpp

# Example: force local inference
curl -s localhost:8081/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"model": "ml-ops/local-model", "messages": [{"role": "user", "content": "ping"}]}'
```

### Fallback chain

The intended fallback order for Phantom (document intelligence):

```
1. ml-ops-api (local GPU, candle inference)
2. llamacpp (local CPU, fallback for no-GPU)
3. securellm-bridge → deepseek (remote, cheapest)
4. securellm-bridge → groq (remote, fastest)
5. securellm-bridge → openai/anthropic (most reliable)
```

If all remote providers are down, Phantom can operate in degraded mode
using only local embeddings (no LLM summarization).

---

## §8 — Post-Incident Checklist

After resolving any incident:

- [ ] Verify all services healthy: `./sentinel/scripts/smoke-test.sh`
- [ ] Run E2E test suite: `cd sentinel && poetry run pytest scenarios/ -m e2e -v`
- [ ] Check NATS stream lag: `nats stream report`
- [ ] Verify Prometheus is scraping: `curl localhost:9090/api/v1/targets | jq '.data.activeTargets[] | .health'`
- [ ] Confirm no alerts firing: `curl localhost:9090/api/v1/alerts | jq '.data.alerts'`
- [ ] Review logs for cascading errors: `docker compose logs --since=1h 2>&1 | grep -i error | head -50`
- [ ] Create backup if database was involved: `FORCE=yes ./sentinel/scripts/backup-postgres.sh`
- [ ] Update ADR if architecture decision changed: `nats run mcp adr_new "..."`
- [ ] Write incident report and link from ROADMAP
