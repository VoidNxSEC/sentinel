#!/usr/bin/env bash
set -euo pipefail

echo "=== Phantom ↔ AI-OS-Agent Integration Test ==="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
PASSED=0
FAILED=0

test_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

test_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

test_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

# 1. Check Phantom API is running
echo "1. Checking Phantom API..."
if curl -f -s http://localhost:8000/health > /dev/null 2>&1; then
    test_pass "Phantom API is responding"
else
    test_fail "Phantom API not responding at http://localhost:8000"
    echo ""
    echo "Start Phantom with:"
    echo "  cd /home/kernelcore/arch/phantom"
    echo "  nix develop -c python -m phantom.api.cortex_api"
    exit 1
fi

# 2. Check /judge endpoint exists
echo ""
echo "2. Checking /judge endpoint..."
if curl -f -s -X POST http://localhost:8000/judge \
    -H "Content-Type: application/json" \
    -d '{}' 2>&1 | grep -q "field required"; then
    test_pass "/judge endpoint exists (validation working)"
else
    test_fail "/judge endpoint not found or broken"
fi

# 3. Send test bundle
echo ""
echo "3. Sending test bundle..."

TEST_BUNDLE=$(cat <<'EOF'
{
  "timestamp": 1737491000,
  "hostname": "test-machine",
  "metrics": {
    "cpu": {
      "usage_percent": 45.2,
      "cores": [40.0, 50.0, 45.0, 45.0]
    },
    "memory": {
      "total_bytes": 16000000000,
      "used_bytes": 8000000000,
      "usage_percent": 50.0
    },
    "thermal": {
      "max_temp_celsius": 68.5,
      "avg_temp_celsius": 65.0
    }
  },
  "alerts": [
    {
      "timestamp": 1737491000,
      "severity": "Warning",
      "category": "Memory",
      "message": "Memory usage high",
      "details": "8GB / 16GB used"
    }
  ],
  "logs": [
    {
      "timestamp": 1737491000,
      "priority": "warning",
      "unit": "systemd",
      "message": "Service started"
    }
  ]
}
EOF
)

RESPONSE=$(curl -s -X POST http://localhost:8000/judge \
    -H "Content-Type: application/json" \
    -d "$TEST_BUNDLE")

if echo "$RESPONSE" | jq -e '.severity' > /dev/null 2>&1; then
    test_pass "Bundle processed successfully"

    # Extract and display key fields
    SEVERITY=$(echo "$RESPONSE" | jq -r '.severity')
    INSIGHTS=$(echo "$RESPONSE" | jq -r '.insights | length')
    ADRS=$(echo "$RESPONSE" | jq -r '.relevant_adrs | length')

    test_info "  Severity: $SEVERITY"
    test_info "  Insights: $INSIGHTS"
    test_info "  Relevant ADRs: $ADRS"
else
    test_fail "Bundle processing failed"
    echo "Response: $RESPONSE"
fi

# 4. Check bundle was saved
echo ""
echo "4. Checking bundle storage..."
if ls /tmp/phantom-bundles/bundle-*.json > /dev/null 2>&1; then
    BUNDLE_COUNT=$(ls /tmp/phantom-bundles/bundle-*.json | wc -l)
    test_pass "Bundles saved ($BUNDLE_COUNT files in /tmp/phantom-bundles/)"
else
    test_fail "No bundles found in /tmp/phantom-bundles/"
fi

# 5. Test with critical scenario
echo ""
echo "5. Testing critical alert scenario..."

CRITICAL_BUNDLE=$(cat <<'EOF'
{
  "timestamp": 1737491100,
  "hostname": "overheating-machine",
  "metrics": {
    "cpu": {
      "usage_percent": 95.0,
      "cores": [98.0, 95.0, 92.0, 96.0]
    },
    "memory": {
      "total_bytes": 16000000000,
      "used_bytes": 14000000000,
      "usage_percent": 87.5
    },
    "thermal": {
      "max_temp_celsius": 82.0,
      "avg_temp_celsius": 78.0
    }
  },
  "alerts": [
    {
      "timestamp": 1737491100,
      "severity": "Critical",
      "category": "Thermal",
      "message": "Temperature critical: 82°C",
      "details": "Exceeds safe threshold"
    }
  ],
  "logs": []
}
EOF
)

CRITICAL_RESPONSE=$(curl -s -X POST http://localhost:8000/judge \
    -H "Content-Type: application/json" \
    -d "$CRITICAL_BUNDLE")

CRITICAL_SEVERITY=$(echo "$CRITICAL_RESPONSE" | jq -r '.severity')
if [ "$CRITICAL_SEVERITY" = "critical" ]; then
    test_pass "Critical severity correctly detected"
else
    test_fail "Expected critical severity, got: $CRITICAL_SEVERITY"
fi

# 6. Check ADR knowledge base integration
echo ""
echo "6. Checking ADR knowledge base..."
if [ -f "/home/kernelcore/arch/adr-ledger/knowledge/knowledge_base.json" ]; then
    test_pass "ADR knowledge base exists"

    ADR_COUNT=$(jq -r '.meta.total_decisions' /home/kernelcore/arch/adr-ledger/knowledge/knowledge_base.json 2>/dev/null || echo "0")
    test_info "  Total ADRs: $ADR_COUNT"
else
    test_fail "ADR knowledge base not found"
    echo "  Run: cd /home/kernelcore/arch/adr-ledger && ./scripts/adr sync"
fi

# Summary
echo ""
echo "==================================="
echo "Test Results:"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo "==================================="

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
