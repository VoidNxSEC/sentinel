# Batch 1 Runbook - Bring-up and Smoke

**Audience**: Operators and release owners
**Scope**: Gate 1 and Gate 2 from `sentinel/docs/go-live-goals.md`
**Last updated**: 2026-03-30

---

## Goal

Prove that the core stack can boot cleanly and pass baseline endpoint checks in the target
environment.

This runbook covers:
- Gate 1: Stack Bring-Up
- Gate 2: Smoke Validation

---

## Prerequisites

Run from repository root (`/home/kernelcore/master`).

Required files:
- `.env`
- `spectre/config/nats-server.conf`
- `spectre/config/nkeys/owasaka.nk`
- `spectre/config/nkeys/ai-agent-os.nk`
- `spectre/config/nkeys/phantom.nk`
- `secrets/tls/ca.crt`
- `secrets/tls/nats.crt`
- `secrets/tls/nats.key`
- `secrets/tls/phantom-api.crt`
- `secrets/tls/phantom-api.key`

Required runtime:
- Docker daemon available
- `curl` available
- `nix` available (if using `nix run` helpers)

---

## Step 0 - Optional Evidence Log

```bash
mkdir -p /tmp/voidnxlabs-go-live
LOG="/tmp/voidnxlabs-go-live/batch1-$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
echo "Evidence log: $LOG"
```

Expected result:
- log file path is printed

---

## Step 1 - Preflight

```bash
cd /home/kernelcore/master
test -f .env
test -f spectre/config/nats-server.conf
test -f spectre/config/nkeys/owasaka.nk
test -f spectre/config/nkeys/ai-agent-os.nk
test -f spectre/config/nkeys/phantom.nk
test -f secrets/tls/ca.crt
test -f secrets/tls/nats.crt
test -f secrets/tls/nats.key
test -f secrets/tls/phantom-api.crt
test -f secrets/tls/phantom-api.key
docker info >/dev/null
```

Expected result:
- no command fails

Blocker if failed:
- missing env file, missing TLS material, or Docker unavailable

---

## Step 2 - Start Core Stack

Use one of the two options below.

Option A (preferred helper):
```bash
nix run .#dev-stack
```

If the stack is already up and the issue is specifically NATS key reload, use:

```bash
nix run .#nats-reload-keys
```

Option B (direct compose):
```bash
docker compose --profile core up -d
```

Inspect status:
```bash
docker compose --profile core ps
```

Expected core services:
- `nats`
- `phantom-api`
- `phantom-proxy`
- `owasaka`
- `ai-agent-os`

Expected health:
- `nats` healthy
- `phantom-api` healthy
- `phantom-proxy` healthy
- `owasaka` healthy
- `ai-agent-os` running

Blocker if failed:
- any core service exits or remains unhealthy after startup window

---

## Step 3 - Smoke Validation

Run existing smoke script:
```bash
nix run .#smoke-test
```

Run explicit endpoint checks (TLS-aware):
```bash
curl -fsS http://localhost:8222/healthz
curl -fsS http://localhost:8222/varz >/dev/null
curl -fsS --cacert secrets/tls/ca.crt https://localhost:8008/health
curl -fsS --cacert secrets/tls/ca.crt https://localhost:8008/ready
curl -fsS --cacert secrets/tls/ca.crt https://localhost:8008/metrics >/dev/null
```

Expected result:
- all checks return success

Note:
- if `nix run .#smoke-test` fails only on `http://localhost:8008/*` but TLS checks pass, treat this as
  a smoke script mismatch and not a stack outage.

Blocker if failed:
- NATS endpoints fail
- Phantom HTTPS endpoints fail with trusted CA
- any endpoint is intermittently failing during repeated checks

---

## Step 4 - Stability and Restart Check

```bash
docker compose --profile core ps --all
for svc in nats phantom-api phantom-proxy owasaka ai-agent-os; do
  cid="$(docker compose --profile core ps -q "$svc")"
  echo -n "$svc restart_count="
  docker inspect -f '{{.RestartCount}}' "$cid"
done
```

Expected result:
- no crash loops
- restart counts are stable (target `0`; investigate `>1`)

Blocker if failed:
- restart count keeps increasing
- service repeatedly transitions between `running` and `exited`

---

## Batch 1 Pass Criteria

Batch 1 is `PASS` only when all criteria are met:
- preflight completed with no missing files or runtime issues
- core stack started and services reached expected health states
- smoke and endpoint checks passed (including TLS checks for phantom)
- no active crash loops or unstable restart behavior

If any criterion fails, mark Batch 1 as `NO-GO` and escalate before Batch 2.

---

## Fast Triage Commands

```bash
docker compose --profile core logs --tail=100 nats
docker compose --profile core logs --tail=100 phantom-api
docker compose --profile core logs --tail=100 phantom-proxy
docker compose --profile core logs --tail=100 owasaka
docker compose --profile core logs --tail=100 ai-agent-os
```

Common causes:
- missing `.env` values
- stale or mismatched `spectre/config/nkeys/*.nk` files
- missing or invalid TLS files under `secrets/tls/`
- NATS auth or cert mismatch between service env and server config

---

## After Batch 1

If Batch 1 is `PASS`:
- keep the stack running and continue to Batch 2 (live E2E)

If Batch 1 is `NO-GO`:
- capture logs and failed commands
- remediate and rerun this runbook from Step 1
