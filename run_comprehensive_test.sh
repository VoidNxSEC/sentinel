#!/usr/bin/env bash
#
# Comprehensive Integration Test Runner
# Neutron + Cerebro + Spectre + Phantom
#
# Usage:
#   ./run_comprehensive_test.sh [OPTIONS]
#
# Options:
#   --quick          Run only fast tests (skip load/performance tests)
#   --chaos-only     Run only chaos engineering tests
#   --no-cleanup     Don't tear down services after tests
#   --verbose        Show detailed test output
#   --help           Show this help message

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.test.yml"
TEST_REPORT_DIR="${SCRIPT_DIR}/reports"
LOG_DIR="${SCRIPT_DIR}/logs"

# Test options
QUICK_MODE=false
CHAOS_ONLY=false
NO_CLEANUP=false
VERBOSE=false

# ========================================
# Helper Functions
# ========================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

print_header() {
    echo ""
    echo "======================================================================"
    echo "  $*"
    echo "======================================================================"
    echo ""
}

show_help() {
    cat << EOF
Comprehensive Integration Test Runner

Usage:
  ./run_comprehensive_test.sh [OPTIONS]

Options:
  --quick          Run only fast tests (skip load/performance tests)
  --chaos-only     Run only chaos engineering tests
  --no-cleanup     Don't tear down services after tests
  --verbose        Show detailed test output
  --help           Show this help message

Examples:
  # Run all tests
  ./run_comprehensive_test.sh

  # Quick test (CI/CD)
  ./run_comprehensive_test.sh --quick

  # Test chaos scenarios only
  ./run_comprehensive_test.sh --chaos-only

  # Verbose output for debugging
  ./run_comprehensive_test.sh --verbose

EOF
}

check_dependencies() {
    log_info "Checking dependencies..."

    local missing_deps=()

    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    fi

    if ! command -v docker-compose &> /dev/null; then
        missing_deps+=("docker-compose")
    fi

    if ! command -v python3 &> /dev/null; then
        missing_deps+=("python3")
    fi

    # Check for poetry or uv
    if ! command -v poetry &> /dev/null && ! command -v uv &> /dev/null; then
        log_warning "Neither poetry nor uv found. Falling back to pip."
        if ! command -v pip3 &> /dev/null; then
            missing_deps+=("pip3")
        fi
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_info "Please install missing dependencies and try again"
        exit 1
    fi

    log_success "All dependencies found"
}

setup_environment() {
    log_info "Setting up test environment..."

    # Create directories
    mkdir -p "${TEST_REPORT_DIR}"
    mkdir -p "${LOG_DIR}"

    # Install Python dependencies using poetry or uv if available
    if command -v poetry &> /dev/null; then
        log_info "Installing dependencies with poetry..."
        poetry install --no-root

        # Try to install optional NATS support
        if poetry install -E nats --no-root 2>/dev/null; then
            log_success "✓ NATS support enabled (Scenario 9 active)"
        else
            log_warning "⚠ NATS support not installed (Scenario 9 will be skipped)"
        fi
    elif command -v uv &> /dev/null; then
        log_info "Installing dependencies with uv..."
        uv pip install -e .

        # Try to install optional NATS support
        if uv pip install nats-py 2>/dev/null; then
            log_success "✓ NATS support enabled (Scenario 9 active)"
        else
            log_warning "⚠ NATS support not installed (Scenario 9 will be skipped)"
        fi
    else
        log_info "Installing dependencies with pip..."
        pip3 install -q -r requirements.txt

        # Try to install optional NATS support
        if pip3 install -q nats-py 2>/dev/null; then
            log_success "✓ NATS support enabled (Scenario 9 active)"
        else
            log_warning "⚠ NATS support not installed (Scenario 9 will be skipped)"
        fi
    fi

    log_success "Environment setup complete"
}

start_services() {
    print_header "Starting Services"

    log_info "Starting services via docker-compose..."
    docker-compose -f "${DOCKER_COMPOSE_FILE}" up -d

    log_info "Waiting for services to be healthy (30s)..."
    sleep 30

    log_info "Checking service health..."

    # Check Phantom
    if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
        log_success "✓ Phantom is healthy"
    else
        log_warning "⚠ Phantom health check failed (might still be starting)"
    fi

    # Check NATS
    if curl -sf http://localhost:8222/healthz > /dev/null 2>&1; then
        log_success "✓ NATS is healthy"
    else
        log_warning "⚠ NATS health check failed"
    fi

    # Check Cerebro (optional)
    if curl -sf http://localhost:8002/health > /dev/null 2>&1; then
        log_success "✓ Cerebro is healthy"
    else
        log_warning "⚠ Cerebro not available (optional)"
    fi

    log_success "Services started"
}

run_tests() {
    print_header "Running Tests"

    local pytest_args=()
    local test_filter=""

    # Verbose mode
    if [ "$VERBOSE" = true ]; then
        pytest_args+=("-v" "-s")
    else
        pytest_args+=("-v")
    fi

    # Test selection
    if [ "$QUICK_MODE" = true ]; then
        log_info "Running quick tests (skipping slow/performance tests)..."
        pytest_args+=("-m" "not slow")
        test_filter="quick"
    elif [ "$CHAOS_ONLY" = true ]; then
        log_info "Running chaos engineering tests only..."
        pytest_args+=("-m" "chaos")
        test_filter="chaos"
    else
        log_info "Running all tests..."
        test_filter="all"
    fi

    # Add report generation
    pytest_args+=(
        "--junitxml=${TEST_REPORT_DIR}/junit-${test_filter}.xml"
        "--tb=short"
    )

    # Run pytest (with poetry if available)
    cd "${SCRIPT_DIR}"

    local pytest_cmd="pytest"
    if command -v poetry &> /dev/null && [ -f "poetry.lock" ]; then
        pytest_cmd="poetry run pytest"
    fi

    if $pytest_cmd "${pytest_args[@]}" test_comprehensive_integration.py; then
        log_success "All tests passed!"
        return 0
    else
        log_error "Some tests failed!"
        return 1
    fi
}

show_logs() {
    print_header "Service Logs (Last 50 lines)"

    log_info "Phantom logs:"
    docker-compose -f "${DOCKER_COMPOSE_FILE}" logs --tail=50 phantom || true

    echo ""
    log_info "NATS logs:"
    docker-compose -f "${DOCKER_COMPOSE_FILE}" logs --tail=20 nats || true
}

cleanup_services() {
    if [ "$NO_CLEANUP" = true ]; then
        log_info "Skipping cleanup (--no-cleanup flag set)"
        log_info "To stop services manually, run:"
        echo "  docker-compose -f ${DOCKER_COMPOSE_FILE} down -v"
        return 0
    fi

    print_header "Cleanup"

    log_info "Stopping services..."
    docker-compose -f "${DOCKER_COMPOSE_FILE}" down -v

    log_success "Cleanup complete"
}

generate_summary() {
    print_header "Test Summary"

    if [ -f "${TEST_REPORT_DIR}/junit-${test_filter:-all}.xml" ]; then
        log_info "Test report saved to:"
        echo "  ${TEST_REPORT_DIR}/junit-${test_filter:-all}.xml"
    fi

    if [ -d "${LOG_DIR}" ]; then
        log_info "Logs saved to:"
        echo "  ${LOG_DIR}/"
    fi

    echo ""
    log_info "To view service logs:"
    echo "  docker-compose -f ${DOCKER_COMPOSE_FILE} logs"

    echo ""
    log_info "To run specific test scenarios:"
    echo "  pytest test_comprehensive_integration.py::test_scenario_01_thermal_spike_happy_path -v"
    echo "  pytest -m chaos  # Run chaos tests only"
    echo "  pytest -m performance  # Run performance tests only"
}

# ========================================
# Main
# ========================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --quick)
                QUICK_MODE=true
                shift
                ;;
            --chaos-only)
                CHAOS_ONLY=true
                shift
                ;;
            --no-cleanup)
                NO_CLEANUP=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    print_header "Comprehensive Integration Test Suite"
    log_info "Testing: Neutron + Cerebro + Spectre + Phantom"

    # Trap cleanup on exit
    trap cleanup_services EXIT

    # Execute test pipeline
    check_dependencies
    setup_environment
    start_services

    # Run tests and capture exit code
    if run_tests; then
        TEST_RESULT=0
    else
        TEST_RESULT=1
        show_logs
    fi

    generate_summary

    # Exit with test result
    exit $TEST_RESULT
}

# Run main function
main "$@"
