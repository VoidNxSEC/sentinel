#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DASHBOARD_FILE="${ROOT_DIR}/spectre/config/grafana/dashboards/ai-agent-os-system-metrics.json"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "PASS  $1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo "FAIL  $1"
}

run_check() {
  local name="$1"
  shift
  echo ""
  echo "=== ${name} ==="
  if "$@"; then
    pass "${name}"
  else
    fail "${name}"
  fi
}

check_observability_baseline() {
  test -f "${ROOT_DIR}/spectre/prometheus.yml"
  test -f "${ROOT_DIR}/spectre/config/grafana/dashboards/voidnxlabs-overview.json"
  grep -q 'nats-exporter' "${ROOT_DIR}/docker-compose.yml"
  grep -q 'prometheus:' "${ROOT_DIR}/docker-compose.yml"
  grep -q 'grafana:' "${ROOT_DIR}/docker-compose.yml"
}

check_ai_agent_dashboard_exists() {
  test -f "${DASHBOARD_FILE}"
}

check_ai_agent_dashboard_content() {
  grep -q 'ai-agent-os' "${DASHBOARD_FILE}"
  grep -Eq 'cpu|memory|thermal|temperature' "${DASHBOARD_FILE}"
}

check_prometheus_live_endpoint() {
  curl -fsS http://localhost:9090/-/healthy >/dev/null
  curl -fsS http://localhost:9090/api/v1/targets >/dev/null
}

echo "=== Batch 4 Metrics Checks ==="
echo "Root: ${ROOT_DIR}"

run_check "Observability baseline wiring" check_observability_baseline
run_check "ai-agent-os dashboard file exists" check_ai_agent_dashboard_exists
run_check "ai-agent-os dashboard content" check_ai_agent_dashboard_content
run_check "Prometheus live endpoint" check_prometheus_live_endpoint

echo ""
echo "Summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"

if [ "${FAIL_COUNT}" -ne 0 ]; then
  echo "Batch 4 Metrics status: NO-GO"
  exit 1
fi

echo "Batch 4 Metrics status: PASS"
