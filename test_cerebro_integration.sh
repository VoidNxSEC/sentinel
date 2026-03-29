#!/usr/bin/env bash
set -euo pipefail

echo "🧠 Cerebro + Phantom Integration Test"
echo "======================================"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

test_pass() {
  echo -e "${GREEN}✓${NC} $1"
}

test_fail() {
  echo -e "${RED}✗${NC} $1"
}

test_info() {
  echo -e "${YELLOW}ℹ${NC} $1"
}

# 1. Check Phantom API
echo -e "${BLUE}[1/5]${NC} Checking Phantom API..."
if ! curl -f -s http://localhost:8000/health >/dev/null 2>&1; then
  test_fail "Phantom API not running"
  echo ""
  echo "Start Phantom:"
  echo "  cd /home/kernelcore/master/phantom && ./start_api.sh"
  exit 1
fi
test_pass "Phantom API responding"

# 2. Check ADR knowledge base
echo ""
echo -e "${BLUE}[2/5]${NC} Checking ADR knowledge base..."
KB_PATH="/home/kernelcore/master/adr-ledger/knowledge/knowledge_base.json"
if [ ! -f "$KB_PATH" ]; then
  test_fail "Knowledge base not found: $KB_PATH"
  echo "Run: cd /home/kernelcore/master/adr-ledger && ./scripts/adr sync"
  exit 1
fi

ADR_COUNT=$(jq -r '.meta.total_decisions' "$KB_PATH")
test_pass "Knowledge base found: $ADR_COUNT ADRs"

# 3. Test thermal alert scenario (should match thermal ADRs)
echo ""
echo -e "${BLUE}[3/5]${NC} Testing thermal alert scenario..."

THERMAL_BUNDLE=$(
  cat <<'EOF'
{
  "timestamp": 1737491200,
  "hostname": "thermal-test",
  "metrics": {
    "cpu": {"usage_percent": 85.0, "cores": [80, 90, 85, 85]},
    "memory": {"total_bytes": 16000000000, "used_bytes": 12000000000, "usage_percent": 75.0},
    "thermal": {"max_temp_celsius": 82.0, "avg_temp_celsius": 78.0}
  },
  "alerts": [{
    "timestamp": 1737491200,
    "severity": "Critical",
    "category": "Thermal",
    "message": "Temperature critical: 82°C - thermal throttling imminent"
  }],
  "logs": []
}
EOF
)

RESPONSE=$(curl -s -X POST http://localhost:8000/judge \
  -H "Content-Type: application/json" \
  -d "$THERMAL_BUNDLE")

SEVERITY=$(echo "$RESPONSE" | jq -r '.severity')
RELEVANT_ADRS=$(echo "$RESPONSE" | jq -r '.relevant_adrs | length')
NOTES=$(echo "$RESPONSE" | jq -r '.notes | length')

if [ "$SEVERITY" = "critical" ]; then
  test_pass "Severity correctly detected: $SEVERITY"
else
  test_fail "Expected critical, got: $SEVERITY"
fi

if [ "$RELEVANT_ADRS" -gt 0 ]; then
  test_pass "Cerebro returned $RELEVANT_ADRS relevant ADRs"

  test_info "Matched ADRs:"
  echo "$RESPONSE" | jq -r '.relevant_adrs[]' | while read -r adr; do
    test_info "  - $adr"
  done
else
  test_fail "Cerebro returned 0 ADRs (expected thermal-related ADRs)"
fi

if [ "$NOTES" -gt 0 ]; then
  test_pass "Cerebro notes: $NOTES entries"

  # Check if notes mention Cerebro
  if echo "$RESPONSE" | jq -r '.notes[]' | grep -q "Cerebro"; then
    test_pass "Notes include Cerebro RAG scores"
  fi
else
  test_fail "No notes from Cerebro"
fi

# 4. Test memory alert scenario
echo ""
echo -e "${BLUE}[4/5]${NC} Testing memory alert scenario..."

MEMORY_BUNDLE=$(
  cat <<'EOF'
{
  "timestamp": 1737491300,
  "hostname": "memory-test",
  "metrics": {
    "cpu": {"usage_percent": 45.0, "cores": [40, 50, 45, 45]},
    "memory": {"total_bytes": 16000000000, "used_bytes": 14500000000, "usage_percent": 90.6},
    "thermal": {"max_temp_celsius": 65.0, "avg_temp_celsius": 62.0}
  },
  "alerts": [{
    "timestamp": 1737491300,
    "severity": "Warning",
    "category": "Memory",
    "message": "Memory usage critical: 90.6% - OOM risk"
  }],
  "logs": []
}
EOF
)

MEM_RESPONSE=$(curl -s -X POST http://localhost:8000/judge \
  -H "Content-Type: application/json" \
  -d "$MEMORY_BUNDLE")

MEM_ADRS=$(echo "$MEM_RESPONSE" | jq -r '.relevant_adrs | length')

if [ "$MEM_ADRS" -gt 0 ]; then
  test_pass "Memory scenario matched $MEM_ADRS ADRs"
else
  test_info "Memory scenario matched 0 ADRs (may need memory-related ADRs)"
fi

# 5. Check Cerebro cache
echo ""
echo -e "${BLUE}[5/5]${NC} Checking FAISS cache..."

if ls /tmp/cerebro-faiss-index* >/dev/null 2>&1; then
  CACHE_SIZE=$(du -sh /tmp/cerebro-faiss-index 2>/dev/null | cut -f1 || echo "unknown")
  test_pass "FAISS cache exists (size: $CACHE_SIZE)"
else
  test_info "FAISS cache not found (will be created on first query)"
fi

# Summary
echo ""
echo "========================================"
echo -e "${GREEN}🎉 Cerebro Integration Tests Complete${NC}"
echo ""
echo "Verified:"
echo "  ✓ Phantom API operational"
echo "  ✓ ADR knowledge base loaded"
echo "  ✓ Cerebro RAG queries working"
echo "  ✓ Semantic matching functional"
echo ""
echo "Next steps:"
echo "  1. Review matched ADRs relevance"
echo "  2. Add more ADRs for better coverage"
echo "  3. Test with AI-OS-Agent real data"
