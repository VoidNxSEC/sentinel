# NATS Key Reload Runbook

**Audience**: operators and maintainers
**Scope**: recreate NATS and NATS-facing containers with the currently approved key material
**Last updated**: 2026-04-02

---

## Goal

Bring NATS and its clients back up with the key material that is already approved in the repo.

This runbook is for the case where:
- `spectre/config/nkeys/*.nk` already exists;
- `spectre/config/nats-server.conf` already contains the matching public keys;
- we need to force a clean recreate of NATS and the main clients so they reload the current keys.

It is not a rotation runbook. If the keys changed, run `sentinel/scripts/rotate-nkeys.sh` first.

---

## Source Of Truth

The key material used by the running stack is:
- private seeds for mounted runtime files: `spectre/config/nkeys/*.nk`
- public keys allowed by the server: `spectre/config/nats-server.conf`
- encrypted seed bundle for recovery/audit: `secrets/nkeys.env.enc`

The helper below validates that the `.nk` headers still match the public keys declared in
`nats-server.conf` before it recreates any container.

---

## Run

Preferred helper:

```bash
nix run .#nats-reload-keys
```

Direct execution:

```bash
cd /home/kernelcore/master/sentinel
bash scripts/reload-nats-keys.sh
```

Default recreated services:
- `nats`
- `phantom-api`
- `phantom-proxy`
- `owasaka`
- `ai-agent-os`

Optional extra services:

```bash
cd /home/kernelcore/master/sentinel
bash scripts/reload-nats-keys.sh nats phantom-api phantom-proxy owasaka ai-agent-os cerebro securellm-bridge
```

---

## What It Checks

1. required files exist:
   - `spectre/config/nats-server.conf`
   - `secrets/tls/ca.crt`
   - `secrets/tls/nats.crt`
   - `secrets/tls/nats.key`
2. every `.nk` file for:
   - `owasaka`
   - `ai-agent-os`
   - `phantom`
   - `phantom-soc`
   - `cerebro`
   - `securellm-bridge`
   matches the public key currently wired into `nats-server.conf`
3. recreates the selected NATS-facing services with:
   - `docker compose --profile core --profile intelligence up -d --force-recreate ...`
4. waits for healthy/running state
5. rechecks:
   - `http://localhost:8222/healthz`
   - `https://localhost:8008/health` with the local CA when `phantom-proxy` is included

---

## Expected Result

Success looks like:
- all `.nk` files match the NATS authorization config;
- `nats` returns `healthy`;
- `phantom-api`, `phantom-proxy`, and `owasaka` return `healthy`;
- `ai-agent-os` returns `running`;
- the NATS and Phantom TLS health endpoints answer successfully.

If the helper fails before the recreate step:
- fix the key mismatch first;
- do not force a restart while the server config and client seeds disagree.

If the helper fails after recreate:
- inspect `docker compose logs --tail=80 <service>`;
- start with `nats`, `phantom-api`, `owasaka`, and `ai-agent-os`.

---

## Relationship To Rotation

Use this order when keys actually change:

1. `bash sentinel/scripts/rotate-nkeys.sh`
2. review `spectre/config/nats-server.conf`
3. verify `secrets/nkeys.env.enc` updated correctly
4. `nix run .#nats-reload-keys`

This keeps rotation and runtime reload as two explicit operational steps.
