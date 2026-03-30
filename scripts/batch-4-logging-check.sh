#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

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

check_json_logging_wiring() {
  grep -R -E 'tracing_subscriber|json\(' \
    "${ROOT_DIR}/ai-agent-os" \
    "${ROOT_DIR}/securellm-bridge" \
    "${ROOT_DIR}/spectre" >/dev/null
}

check_log_aggregation_wiring() {
  test -f "${ROOT_DIR}/spectre/config/loki-config.yml"
  grep -q 'loki:' "${ROOT_DIR}/docker-compose.yml"
  grep -q 'promtail:' "${ROOT_DIR}/docker-compose.yml"
}

check_correlation_id_wiring() {
  grep -R -n 'correlation_id' \
    "${ROOT_DIR}/sentinel" \
    "${ROOT_DIR}/phantom" \
    "${ROOT_DIR}/spectre" \
    "${ROOT_DIR}/securellm-bridge" >/dev/null
}

check_log_stack_live_endpoints() {
  curl -fsS http://localhost:3100/ready >/dev/null
}

echo "=== Batch 4 Logging Checks ==="
echo "Root: ${ROOT_DIR}"

run_check "Structured JSON logging wiring" check_json_logging_wiring
run_check "Central log aggregation wiring" check_log_aggregation_wiring
run_check "Correlation ID wiring" check_correlation_id_wiring
run_check "Loki live endpoint" check_log_stack_live_endpoints

echo ""
echo "Summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"

if [ "${FAIL_COUNT}" -ne 0 ]; then
  echo "Batch 4 Logging status: NO-GO"
  exit 1
fi

echo "Batch 4 Logging status: PASS"
