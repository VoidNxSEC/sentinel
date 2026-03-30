#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SENTINEL_DIR="${ROOT_DIR}/sentinel"
CA_CERT="${ROOT_DIR}/secrets/tls/ca.crt"
NATS_CONF="${ROOT_DIR}/spectre/config/nats-server.conf"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"

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

check_nats_auth() {
  cd "${SENTINEL_DIR}"
  NATS_URL="tls://localhost:4222" \
  NATS_CA_FILE="${ROOT_DIR}/secrets/tls/ca.crt" \
  NATS_CLIENT_CERT_FILE="${ROOT_DIR}/secrets/tls/owasaka.crt" \
  NATS_CLIENT_KEY_FILE="${ROOT_DIR}/secrets/tls/owasaka.key" \
  poetry run pytest scenarios/test_nats_auth.py -m e2e -v
}

check_phantom_tls() {
  test -f "${CA_CERT}"
  curl -fsS --cacert "${CA_CERT}" https://localhost:8008/health >/dev/null
  curl -fsS --cacert "${CA_CERT}" https://localhost:8008/ready >/dev/null
  curl -fsS --cacert "${CA_CERT}" https://localhost:8008/metrics >/dev/null
}

check_nats_mtls_wiring() {
  grep -q '^tls[[:space:]]*{' "${NATS_CONF}"
  grep -q 'verify:[[:space:]]*true' "${NATS_CONF}"
  grep -q 'NATS_URL=tls://' "${COMPOSE_FILE}"
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

echo "=== Batch 3 Security Checks ==="
echo "Root: ${ROOT_DIR}"

run_check "NATS auth E2E" check_nats_auth
run_check "Phantom TLS endpoint validation" check_phantom_tls
run_check "NATS mTLS wiring readiness" check_nats_mtls_wiring

echo ""
echo "Summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"

if [ "${FAIL_COUNT}" -ne 0 ]; then
  echo "Batch 3 status: NO-GO"
  exit 1
fi

echo "Batch 3 status: PASS"
