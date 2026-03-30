# Batch 2 Runbook - Live E2E Validation

**Audience**: Operators and release owners
**Scope**: Gate 3 from `sentinel/docs/go-live-goals.md`
**Last updated**: 2026-03-30

---

## Goal

Prove the critical event flow works against the already-running live stack.

This runbook covers:
- Spectre E2E (`scenarios/test_spectre_e2e.py`)
- phantom-soc E2E (`scenarios/test_phantom_soc_e2e.py`)

---

## Prerequisites

Run from repository root (`/home/kernelcore/master`).

Required state:
- Batch 1 is `PASS`
- core stack remains up (`nats`, `phantom-api`, `phantom-proxy`, `owasaka`, `ai-agent-os`)
- `secrets/tls/ca.crt` exists for trusted HTTPS checks

Quick preflight:

```bash
cd /home/kernelcore/master
docker compose --profile core ps
curl -fsS http://localhost:8222/healthz
curl -fsS --cacert secrets/tls/ca.crt https://localhost:8008/health
```

Expected result:
- all commands succeed

---

## Step 1 - Run Batch 2 via `nix develop --command`

```bash
nix develop --command bash -lc '
  cd /home/kernelcore/master/sentinel
  SENTINEL_USE_LIVE_STACK=1 \
  SENTINEL_CA_CERT=/home/kernelcore/master/secrets/tls/ca.crt \
  poetry run pytest \
    scenarios/test_spectre_e2e.py \
    scenarios/test_phantom_soc_e2e.py \
    -m e2e -v
'
```

Important:
- `SENTINEL_USE_LIVE_STACK=1` disables `docker-compose.test.yml` startup/teardown in `conftest.py`
- `SENTINEL_CA_CERT` lets HTTPS checks trust the local CA without insecure TLS flags
- install the Python deps with `poetry install --no-root -E nats` before the first run if the virtualenv is not ready

---

## Step 2 - Optional focused reruns

Spectre only:

```bash
nix develop --command bash -lc '
  cd /home/kernelcore/master/sentinel
  SENTINEL_USE_LIVE_STACK=1 \
  SENTINEL_CA_CERT=/home/kernelcore/master/secrets/tls/ca.crt \
  poetry run pytest scenarios/test_spectre_e2e.py -m e2e -v
'
```

phantom-soc only:

```bash
nix develop --command bash -lc '
  cd /home/kernelcore/master/sentinel
  SENTINEL_USE_LIVE_STACK=1 \
  SENTINEL_CA_CERT=/home/kernelcore/master/secrets/tls/ca.crt \
  poetry run pytest scenarios/test_phantom_soc_e2e.py -m e2e -v
'
```

---

## Batch 2 Pass Criteria

Batch 2 is `PASS` only when:
- both test files complete with no failing tests
- no unexpected service restarts occur during execution
- published event schema, routing, and ordering assertions pass

Expected skips:
- `test_phantom_soc_scheduler_binary_exists` skips until `phantom-soc/control-plane` is built locally
- `test_phantom_soc_logviewer_headless` skips without `DISPLAY` or `WAYLAND_DISPLAY`
- `test_phantom_soc_live_dispatch` may be deferred when the local data-plane environment is not prepared

If any criterion fails, mark Batch 2 as `NO-GO` and escalate before Batch 3.

---

## Fast Triage

```bash
docker compose --profile core logs --tail=120 nats
docker compose --profile core logs --tail=120 owasaka
docker compose --profile core logs --tail=120 ai-agent-os
docker compose --profile core logs --tail=120 phantom-api
```

Common causes:
- wrong NATS URL or unavailable local port mapping
- local CA path not set for HTTPS checks
- stale background `docker-compose.test.yml` process from previous test runs
