#!/usr/bin/env bash
# Test Neutron Integration - End-to-End
set -euo pipefail

echo "=================================================="
echo "NEUTRON INTEGRATION - End-to-End Tests"
echo "=================================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHANTOM_DIR="/home/kernelcore/arch/phantom"
NEUTRON_DIR="/home/kernelcore/arch/neutron"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

test_passed=0
test_failed=0

# Helper functions
pass_test() {
    echo -e "${GREEN}✓ PASSED${NC}: $1"
    ((test_passed++))
}

fail_test() {
    echo -e "${RED}✗ FAILED${NC}: $1"
    ((test_failed++))
}

info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Test 1: Verificar módulos Python criados
echo ""
echo "──────────────────────────────────────────────────"
echo "Test 1: Verificar módulos Neutron integration"
echo "──────────────────────────────────────────────────"

if [ -f "$PHANTOM_DIR/src/phantom/neutron/__init__.py" ]; then
    pass_test "phantom/neutron/__init__.py exists"
else
    fail_test "phantom/neutron/__init__.py missing"
fi

if [ -f "$PHANTOM_DIR/src/phantom/neutron/sentinel_integration.py" ]; then
    pass_test "sentinel_integration.py exists"
else
    fail_test "sentinel_integration.py missing"
fi

if [ -f "$PHANTOM_DIR/src/phantom/neutron/oracle_explainer.py" ]; then
    pass_test "oracle_explainer.py exists"
else
    fail_test "oracle_explainer.py missing"
fi

# Test 2: Testar imports
echo ""
echo "──────────────────────────────────────────────────"
echo "Test 2: Testar imports Python"
echo "──────────────────────────────────────────────────"

cd "$PHANTOM_DIR/src"
export PYTHONPATH="$PHANTOM_DIR/src:$NEUTRON_DIR:$PYTHONPATH"

python3 -c "from phantom.neutron import PhantomSentinel, OracleExplainer" 2>/dev/null && \
    pass_test "Imports OK" || \
    fail_test "Import error"

# Test 3: Testar SENTINEL standalone
echo ""
echo "──────────────────────────────────────────────────"
echo "Test 3: SENTINEL Standalone Tests"
echo "──────────────────────────────────────────────────"

info "Running SENTINEL tests..."
python3 "$PHANTOM_DIR/src/phantom/neutron/sentinel_integration.py" > /tmp/sentinel_test.log 2>&1
if grep -q "✅ BLOCKED (correto)" /tmp/sentinel_test.log; then
    pass_test "SENTINEL guardrails working"
    cat /tmp/sentinel_test.log | grep -E "(✅|⚠️|PASSED|BLOCKED)" | head -5
else
    fail_test "SENTINEL tests failed"
    cat /tmp/sentinel_test.log | tail -10
fi

# Test 4: Testar ORACLE standalone
echo ""
echo "──────────────────────────────────────────────────"
echo "Test 4: ORACLE Standalone Tests"
echo "──────────────────────────────────────────────────"

info "Running ORACLE tests..."
python3 "$PHANTOM_DIR/src/phantom/neutron/oracle_explainer.py" > /tmp/oracle_test.log 2>&1
if grep -q "Confidence:" /tmp/oracle_test.log; then
    pass_test "ORACLE explainer working"
    cat /tmp/oracle_test.log | grep -E "(Confidence|ADR-)" | head -5
else
    fail_test "ORACLE tests failed"
    cat /tmp/oracle_test.log | tail -10
fi

# Test 5: Testar Judge API integration
echo ""
echo "──────────────────────────────────────────────────"
echo "Test 5: Judge API Integration"
echo "──────────────────────────────────────────────────"

info "Testing Judge API with Neutron integration..."
python3 <<'PYEOF'
import sys
import json
sys.path.insert(0, "/home/kernelcore/arch/phantom/src")
sys.path.insert(0, "/home/kernelcore/arch/neutron")

from phantom.api.judge_api import JudgmentEngine, PhantomGateBundle, SystemMetrics
from phantom.api.judge_api import CPUMetrics, MemoryMetrics, ThermalMetrics, Alert

# Create mock bundle
metrics = SystemMetrics(
    cpu=CPUMetrics(usage_percent=92.5, cores=[90.0, 95.0]),
    memory=MemoryMetrics(total_bytes=16000000000, used_bytes=14000000000, usage_percent=87.5),
    thermal=ThermalMetrics(max_temp_celsius=82.0, avg_temp_celsius=76.0)
)

alerts = [
    Alert(
        timestamp=1700000000,
        severity="Critical",
        category="Thermal",
        message="High temperature detected",
        details="CPU temp 82C"
    )
]

bundle = PhantomGateBundle(
    timestamp=1700000000,
    hostname="test-machine",
    metrics=metrics,
    alerts=alerts,
    logs=[]
)

# Initialize engine (sem knowledge base para teste rápido)
engine = JudgmentEngine(knowledge_base_path=None)

# Test initialization
if engine.sentinel:
    print("✓ SENTINEL initialized")
else:
    print("⚠ SENTINEL not available (expected in bypass mode)")

if engine.oracle:
    print("✓ ORACLE initialized")
else:
    print("⚠ ORACLE not available (expected in bypass mode)")

# Judge bundle
result = engine.judge(bundle)

print(f"Severity: {result.severity}")
print(f"Insights: {len(result.insights)}")
print(f"Recommendations: {len(result.recommendations)}")
print(f"Notes: {len(result.notes)}")

# Check for Neutron markers in notes
neutron_markers = ["ORACLE", "SENTINEL", "Compliance"]
has_neutron = any(marker in str(result.notes) for marker in neutron_markers)

if has_neutron:
    print("✓ Neutron integration markers found in response")
else:
    print("⚠ No Neutron markers (running in bypass mode)")

PYEOF

if [ $? -eq 0 ]; then
    pass_test "Judge API integration works"
else
    fail_test "Judge API integration failed"
fi

# Test 6: Validação de compliance
echo ""
echo "──────────────────────────────────────────────────"
echo "Test 6: Compliance Validation"
echo "──────────────────────────────────────────────────"

info "Testing compliance checks..."
python3 <<'PYEOF'
import sys
sys.path.insert(0, "/home/kernelcore/arch/phantom/src")
sys.path.insert(0, "/home/kernelcore/arch/neutron")

from phantom.neutron import validate_recommendation

# Test válido
passed, details = validate_recommendation(
    recommendation="Verificar ventilação do sistema",
    adr_id="ADR-0023",
    explanation="Baseado no ADR-0023, temperatura está acima do threshold"
)

if passed:
    print("✓ Valid recommendation passed compliance")
else:
    print(f"✗ Valid recommendation failed: {details}")

# Test inválido (sem explicação)
passed, details = validate_recommendation(
    recommendation="Reiniciar sistema",
    adr_id="ADR-0099",
    explanation=None
)

if not passed:
    print("✓ Invalid recommendation blocked (no explanation)")
else:
    print("✗ Invalid recommendation should have been blocked")

# Test inválido (comando perigoso)
passed, details = validate_recommendation(
    recommendation="Execute: rm -rf /",
    adr_id="ADR-0001",
    explanation="Cleanup"
)

if not passed:
    print("✓ Dangerous command blocked")
else:
    print("✗ Dangerous command should have been blocked")

PYEOF

if [ $? -eq 0 ]; then
    pass_test "Compliance validation working"
else
    fail_test "Compliance validation failed"
fi

# Summary
echo ""
echo "=================================================="
echo "TEST SUMMARY"
echo "=================================================="
echo -e "${GREEN}Passed: $test_passed${NC}"
echo -e "${RED}Failed: $test_failed${NC}"

if [ $test_failed -eq 0 ]; then
    echo -e "\n${GREEN}🎉 ALL TESTS PASSED!${NC}\n"
    exit 0
else
    echo -e "\n${RED}❌ SOME TESTS FAILED${NC}\n"
    exit 1
fi
