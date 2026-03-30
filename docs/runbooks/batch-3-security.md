# Batch 3 Runbook - Security Validation

**Audience**: Operators and release owners
**Scope**: Gate 4 from `sentinel/docs/go-live-goals.md`
**Last updated**: 2026-03-30

---

## Goal

Validate the live stack security baseline before go-live.

This batch covers:
- NATS NKey auth enforcement
- Phantom HTTPS validation with trusted CA
- NATS mTLS wiring readiness

---

## Prerequisites

Run from repository root (`/home/kernelcore/master`).

Required state:
- Batch 1 is `PASS`
- Batch 2 is `PASS`
- core stack is still running
- `secrets/tls/ca.crt` exists
- `spectre/config/nkeys/*.nk` exists or equivalent seed env vars are available

Quick preflight:

```bash
cd /home/kernelcore/master
docker compose --profile core ps
curl -fsS http://localhost:8222/healthz
curl -fsS --cacert secrets/tls/ca.crt https://localhost:8008/health
```

---

## Step 1 - Run Batch 3

Preferred helper:

```bash
nix run .#batch-3-security
```

Direct execution:

```bash
cd /home/kernelcore/master/sentinel
bash scripts/batch-3-security-check.sh
```

What it does:
1. runs `scenarios/test_nats_auth.py` against the live NATS server
2. validates Phantom HTTPS endpoints with the local CA
3. checks whether NATS mTLS is actually wired into server config and compose clients

---

## Pass Criteria

Batch 3 is `PASS` only when:
- NATS auth E2E passes
- Phantom HTTPS checks pass with the trusted CA
- NATS mTLS wiring readiness passes

If any criterion fails, Batch 3 is `NO-GO`.

---

## Current Local Constraint

The local stack is still expected to fail the NATS mTLS readiness check until:
- `spectre/config/nats-server.conf` restores the active `tls { ... verify: true }` block
- compose clients stop using plain `nats://` and are wired for TLS client auth

This is a real deployment gap, not a test gap.
