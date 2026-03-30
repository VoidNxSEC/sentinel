#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
PASS=0; FAIL=0

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CA_CERT="${SCRIPT_DIR}/../../secrets/tls/ca.crt"
TLS_ARGS=()
[ -f "$CA_CERT" ] && TLS_ARGS=(--cacert "$CA_CERT")

check_http() {
    local name="$1" url="$2" expected="${3:-200}"
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
    if [ "$status" = "$expected" ]; then
        echo -e "  ${GREEN}✓${NC} $name ($url) → $status"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} $name ($url) → $status (expected $expected)"
        FAIL=$((FAIL + 1))
    fi
}

check_https() {
    local name="$1" url="$2" expected="${3:-200}"
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${TLS_ARGS[@]}" "$url" 2>/dev/null || echo "000")
    if [ "$status" = "$expected" ]; then
        echo -e "  ${GREEN}✓${NC} $name ($url) → $status"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} $name ($url) → $status (expected $expected)"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== voidnxlabs smoke test ==="
echo ""

# Wait for NATS (max 30s)
echo "Waiting for NATS..."
for i in $(seq 1 30); do
    curl -s http://localhost:8222/healthz >/dev/null 2>&1 && break
    sleep 1
done

echo "Checking services:"
check_http  "NATS healthz"    "http://localhost:8222/healthz"
check_http  "NATS varz"       "http://localhost:8222/varz"
check_https "Phantom health"  "https://localhost:8008/health"
check_https "Phantom ready"   "https://localhost:8008/ready"
check_https "Phantom metrics" "https://localhost:8008/metrics"

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
