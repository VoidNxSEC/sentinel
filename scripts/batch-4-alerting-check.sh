#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ALERTS_FILE="${ROOT_DIR}/spectre/config/alerts.yml"

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

check_alert_rules_file() {
  test -f "${ALERTS_FILE}"
  test "$(grep -c '^[[:space:]]*- alert:' "${ALERTS_FILE}")" -ge 10
}

check_prometheus_alerting_wiring() {
  grep -q 'rule_files:' "${ROOT_DIR}/spectre/prometheus.yml"
  grep -q 'alerts.yml' "${ROOT_DIR}/spectre/prometheus.yml"
}

check_thermal_alert_path() {
  grep -R -n -E 'thermal|temperature' \
    "${ROOT_DIR}/spectre/config/alerts.yml" \
    "${ROOT_DIR}/ai-agent-os" \
    "${ROOT_DIR}/phantom-soc" >/dev/null
}

check_prometheus_rules_endpoint() {
  curl -fsS http://localhost:9090/api/v1/rules >/dev/null
  curl -fsS http://localhost:9090/api/v1/alerts >/dev/null
}

echo "=== Batch 4 Alerting Checks ==="
echo "Root: ${ROOT_DIR}"

run_check "Alert rules file" check_alert_rules_file
run_check "Prometheus alerting wiring" check_prometheus_alerting_wiring
run_check "Thermal alert path" check_thermal_alert_path
run_check "Prometheus alert endpoints" check_prometheus_rules_endpoint

echo ""
echo "Summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"

if [ "${FAIL_COUNT}" -ne 0 ]; then
  echo "Batch 4 Alerting status: NO-GO"
  exit 1
fi

echo "Batch 4 Alerting status: PASS"
