# Batch 4 Runbook - Alerting Validation

**Audience**: Operators and release owners
**Scope**: Block E from the operational attack plan
**Last updated**: 2026-03-30

---

## Goal

Validate that alerting is operational, not just configured on disk.

This block covers:
- alert rules file presence
- Prometheus rule wiring
- thermal alert path readiness
- Prometheus alert/rule endpoints

---

## Run

Preferred helper:

```bash
nix run .#batch-4-alerting
```

Direct execution:

```bash
cd /home/kernelcore/master/sentinel
bash scripts/batch-4-alerting-check.sh
```

---

## Pass Criteria

Batch 4 Alerting is `PASS` only when:
- alert rules are present and wired into Prometheus
- the thermal alert path is implemented or explicitly evidenced
- live Prometheus rule and alert endpoints respond

If any criterion fails, this block is `NO-GO`.
