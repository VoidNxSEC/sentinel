#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
PASS=0; FAIL=0

check() {
    local name="$1" url="$2" expected="${3:-200}"
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
    if [ "$status" = "$expected" ]; then
        echo -e "  ${GREEN}✓${NC} $name ($url) → $status"
        ((PASS++))
    else
        echo -e "  ${RED}✗${NC} $name ($url) → $status (expected $expected)"
        ((FAIL++))
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
check "NATS healthz"     "http://localhost:8222/healthz"
check "NATS varz"        "http://localhost:8222/varz"
check "Phantom health"   "http://localhost:8008/health"
check "Phantom ready"    "http://localhost:8008/ready"
check "Phantom metrics"  "http://localhost:8008/metrics"

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
