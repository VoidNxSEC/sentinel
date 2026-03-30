# Batch 4 Runbook - Logging Validation

**Audience**: Operators and release owners
**Scope**: Block D from the operational attack plan
**Last updated**: 2026-03-30

---

## Goal

Close the logging gap with structured logs, centralized aggregation, and correlation.

This block covers:
- structured JSON logging wiring
- centralized aggregation wiring
- correlation ID propagation
- live Loki readiness

---

## Run

Preferred helper:

```bash
nix run .#batch-4-logging
```

Direct execution:

```bash
cd /home/kernelcore/master/sentinel
bash scripts/batch-4-logging-check.sh
```

---

## Pass Criteria

Batch 4 Logging is `PASS` only when:
- required services are configured for JSON logs
- centralized log aggregation is wired in compose
- correlation IDs are present in the code path
- the log backend is reachable live

If any criterion fails, this block is `NO-GO`.
