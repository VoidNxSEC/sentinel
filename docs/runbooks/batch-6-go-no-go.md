# Batch 6 Runbook — Go / No-Go

**Audience**: release owner, operators, maintainers
**Scope**: final deployment decision after Batches 1 through 5
**Last updated**: 2026-03-30

## Goal

Convert the already executed operational gates into a final, reproducible deployment decision.

Batch 6 is `GO` only when:
- all required gates are recorded as `PASS`;
- the live stack still answers the critical NATS and Phantom TLS health checks;
- no open blocker remains outside the explicitly deferred M7 thermal UI path;
- post-release distribution work in `M8` remains outside the production go-live gate.

## Run

Preferred helper:

```bash
nix run .#batch-6-go-no-go
```

Direct execution:

```bash
cd /home/kernelcore/master/sentinel
bash scripts/batch-6-go-no-go-check.sh
```

## What It Checks

1. reads `sentinel/ROADMAP.md` and verifies the recorded `PASS` state for:
   - Batch 1
   - Batch 2
   - Batch 3
   - Batch 5
   - Gate 5 Secrets
   - Block C Metrics
   - Block D Logging
   - Block E Alerting
2. rechecks:
   - `http://localhost:8222/healthz`
   - `https://localhost:8008/health` with the local CA
3. prints the final decision line:
   - `GO` when everything above passes
   - `NO-GO` otherwise

## Latest Result

Local decision passed on 2026-03-30.

- all required gates were recorded as `PASS`
- NATS health returned `{"status":"ok"}`
- Phantom TLS proxy returned `{"status":"operational","version":"0.0.1"}`
- deferred item left outside the go-live gate: `ai-agent-os -> phantom-soc UI` thermal path (`M7`)

## Release Note

Batch 6 does not replace engineering judgment. If a new blocker appears after this check, rerun
the relevant gate and then rerun Batch 6 before deployment.

Documentation sign-off should still review `adr-ledger` as the release-governance source even
though the helper script only validates roadmap gate state plus live core health.
