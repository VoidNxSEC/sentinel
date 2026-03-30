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
- live Loki readiness and query path

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
- Loki can answer a real query against ingested Docker logs

Current implementation target:
- `loki` stores centralized logs for the local stack
- `promtail` tails Docker `json-file` logs from `/var/lib/docker/containers`
- Grafana has a provisioned Loki datasource alongside Prometheus and Jaeger

Operational note:
- bind-mounted observability configs from `spectre/config` must remain readable to the container runtime
  (`0644` on the host is sufficient for the local Docker workflow)

If any criterion fails, this block is `NO-GO`.
