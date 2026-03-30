#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ROADMAP="$ROOT_DIR/sentinel/ROADMAP.md"

pass() {
  printf 'PASS  %s\n' "$1"
}

fail() {
  printf 'FAIL  %s\n' "$1"
  exit 1
}

check_status_line() {
  local label="$1"
  local pattern="$2"
  if rg -q "$pattern" "$ROADMAP"; then
    pass "$label"
  else
    fail "$label"
  fi
}

echo "=== Batch 6 Go/No-Go Check ==="
echo "Root: $ROOT_DIR"
echo

echo "=== Gate status baseline ==="
check_status_line "Batch 1 PASS recorded" '^- Batch 1: `PASS`'
check_status_line "Batch 2 PASS recorded" '^- Batch 2: `PASS`'
check_status_line "Batch 3 PASS recorded" '^- Batch 3: `PASS`'
check_status_line "Batch 5 PASS recorded" '^- Batch 5: `PASS`'
check_status_line "Secrets PASS recorded" '^- Gate 5 Secrets: `PASS`'
check_status_line "Metrics PASS recorded" '^- Block C Metrics: `PASS`'
check_status_line "Logging PASS recorded" '^- Block D Logging: `PASS`'
check_status_line "Alerting PASS recorded" '^- Block E Alerting: `PASS`'
echo

echo "=== Live health recheck ==="
curl -fsS http://localhost:8222/healthz >/dev/null
pass "NATS health"
curl -fsS --cacert "$ROOT_DIR/secrets/tls/ca.crt" https://localhost:8008/health >/dev/null
pass "Phantom TLS health"
echo

echo "=== Decision ==="
echo "GO  All required gates are recorded as PASS and core live health is green."
