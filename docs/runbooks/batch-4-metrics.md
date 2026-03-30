# Batch 4 Runbook - Metrics Completion

**Audience**: Operators and release owners
**Scope**: Block C from the operational attack plan
**Last updated**: 2026-03-30

---

## Goal

Close the metrics gap by delivering the `ai-agent-os` system metrics dashboard and validating the
observability baseline.

This block covers:
- observability stack wiring
- dashboard artifact for `ai-agent-os`
- dashboard content for CPU, memory, and thermal views
- `system.metrics.v1` bridge into Prometheus
- Prometheus live endpoint validation

---

## Run

Preferred helper:

```bash
nix run .#batch-4-metrics
```

Direct execution:

```bash
cd /home/kernelcore/master/sentinel
bash scripts/batch-4-metrics-check.sh
```

---

## Pass Criteria

Batch 4 Metrics is `PASS` only when:
- the observability stack is wired in compose
- the `ai-agent-os` dashboard file exists in repo
- the dashboard contains real system-metrics panels
- Prometheus live endpoints are reachable
- a live `ai_agent_*` series is queryable from Prometheus

Current implementation:
- `ai-agent-os` publishes `system.metrics.v1` on NATS
- `spectre/tools/ai-agent-metrics-bridge` subscribes with NKey auth and exposes `/metrics`
- Prometheus scrapes the bridge as job `ai-agent-os`

If any criterion fails, this block is `NO-GO`.
