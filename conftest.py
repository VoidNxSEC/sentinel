"""
Pytest configuration and fixtures for comprehensive integration tests.

Provides:
- Service orchestration (docker-compose)
- HTTP clients for all services
- Test data loaders
- Performance measurement utilities
- Cleanup hooks
"""

import json
import time
import asyncio
import subprocess
from pathlib import Path
from typing import Dict, Any, Callable

import pytest
import httpx


# ========================================
# Test Configuration
# ========================================

TIMEOUT_DEFAULT = 30.0
TIMEOUT_LONG = 60.0
SERVICE_STARTUP_WAIT = 20  # seconds
SERVICE_HEALTH_CHECK_RETRIES = 30
SERVICE_HEALTH_CHECK_INTERVAL = 2  # seconds

BASE_DIR = Path(__file__).parent
FIXTURES_DIR = BASE_DIR / "fixtures" / "bundles"
DOCKER_COMPOSE_FILE = BASE_DIR / "docker-compose.test.yml"


# ========================================
# Session-scoped Fixtures (Run Once)
# ========================================

@pytest.fixture(scope="session")
def docker_services():
    """
    Start all services via docker-compose at the beginning of test session.
    Tear down at the end.
    """
    print("\n🚀 Starting services via docker-compose...")

    # Start services
    subprocess.run(
        ["docker-compose", "-f", str(DOCKER_COMPOSE_FILE), "up", "-d"],
        check=True,
        cwd=BASE_DIR
    )

    # Wait for services to initialize
    print(f"⏳ Waiting {SERVICE_STARTUP_WAIT}s for services to initialize...")
    time.sleep(SERVICE_STARTUP_WAIT)

    # Verify health checks
    print("🏥 Checking service health...")
    _wait_for_services()

    print("✅ All services ready\n")

    yield

    # Teardown
    print("\n🛑 Shutting down services...")
    subprocess.run(
        ["docker-compose", "-f", str(DOCKER_COMPOSE_FILE), "down", "-v"],
        check=True,
        cwd=BASE_DIR
    )
    print("✅ Services stopped\n")


def _wait_for_services():
    """Wait for all services to be healthy."""
    services = [
        ("Phantom", "http://localhost:8000/health"),
        ("NATS", "http://localhost:8222/healthz"),
    ]

    # Cerebro might not have health endpoint - optional
    optional_services = [
        ("Cerebro", "http://localhost:8002/health"),
    ]

    for name, url in services:
        _wait_for_service(name, url, required=True)

    for name, url in optional_services:
        _wait_for_service(name, url, required=False)


def _wait_for_service(name: str, url: str, required: bool = True):
    """Wait for a specific service to be healthy."""
    for attempt in range(SERVICE_HEALTH_CHECK_RETRIES):
        try:
            response = httpx.get(url, timeout=5.0)
            if response.status_code == 200:
                print(f"  ✓ {name} is healthy")
                return True
        except Exception:
            pass

        time.sleep(SERVICE_HEALTH_CHECK_INTERVAL)

    if required:
        raise RuntimeError(f"❌ {name} failed to become healthy after {SERVICE_HEALTH_CHECK_RETRIES} attempts")
    else:
        print(f"  ⚠ {name} is not available (optional)")
        return False


# ========================================
# Function-scoped Fixtures (Per Test)
# ========================================

@pytest.fixture
async def phantom_client(docker_services):
    """HTTP client for Phantom Judge API."""
    async with httpx.AsyncClient(
        base_url="http://localhost:8000",
        timeout=TIMEOUT_DEFAULT
    ) as client:
        yield client


@pytest.fixture
async def cerebro_client(docker_services):
    """HTTP client for Cerebro RAG API."""
    async with httpx.AsyncClient(
        base_url="http://localhost:8002",
        timeout=TIMEOUT_DEFAULT
    ) as client:
        yield client


@pytest.fixture
def nats_url(docker_services) -> str:
    """NATS connection URL."""
    return "nats://localhost:4222"


@pytest.fixture
def load_bundle() -> Callable[[str], Dict[str, Any]]:
    """
    Factory fixture to load test bundle JSON files.

    Usage:
        bundle = load_bundle("thermal_critical.json")
    """
    def _load(filename: str) -> Dict[str, Any]:
        path = FIXTURES_DIR / filename
        if not path.exists():
            raise FileNotFoundError(f"Bundle not found: {path}")
        return json.loads(path.read_text())

    return _load


@pytest.fixture
def performance_timer():
    """
    Context manager for measuring performance.

    Usage:
        with performance_timer() as timer:
            await do_something()
        assert timer.elapsed_ms < 500
    """
    class Timer:
        def __init__(self):
            self.start_time = None
            self.end_time = None
            self.elapsed_ms = None

        def __enter__(self):
            self.start_time = time.perf_counter()
            return self

        def __exit__(self, exc_type, exc_val, exc_tb):
            self.end_time = time.perf_counter()
            self.elapsed_ms = (self.end_time - self.start_time) * 1000

    return Timer


@pytest.fixture
def assert_performance():
    """
    Helper to assert performance requirements.

    Usage:
        with assert_performance(max_latency_ms=500):
            await do_something()
    """
    class PerformanceAssertion:
        def __init__(self, max_latency_ms: int):
            self.max_latency_ms = max_latency_ms
            self.start_time = None

        def __enter__(self):
            self.start_time = time.perf_counter()
            return self

        def __exit__(self, exc_type, exc_val, exc_tb):
            elapsed_ms = (time.perf_counter() - self.start_time) * 1000
            assert elapsed_ms < self.max_latency_ms, \
                f"Performance assertion failed: {elapsed_ms:.2f}ms > {self.max_latency_ms}ms"

    return PerformanceAssertion


# ========================================
# Helper Functions
# ========================================

def wait_for_condition(
    condition: Callable[[], bool],
    timeout: float = 10.0,
    interval: float = 0.5,
    error_msg: str = "Condition not met within timeout"
):
    """
    Wait for a condition to become true.

    Args:
        condition: Callable that returns True when condition is met
        timeout: Maximum time to wait in seconds
        interval: Time between checks in seconds
        error_msg: Error message if timeout is reached
    """
    start_time = time.time()
    while time.time() - start_time < timeout:
        if condition():
            return True
        time.sleep(interval)
    raise TimeoutError(error_msg)


async def wait_for_condition_async(
    condition: Callable[[], bool],
    timeout: float = 10.0,
    interval: float = 0.5,
    error_msg: str = "Condition not met within timeout"
):
    """Async version of wait_for_condition."""
    start_time = time.time()
    while time.time() - start_time < timeout:
        if condition():
            return True
        await asyncio.sleep(interval)
    raise TimeoutError(error_msg)


# ========================================
# Pytest Configuration
# ========================================

def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line(
        "markers", "slow: marks tests as slow (deselect with '-m \"not slow\"')"
    )
    config.addinivalue_line(
        "markers", "chaos: marks tests that involve failure injection"
    )
    config.addinivalue_line(
        "markers", "performance: marks tests that measure performance"
    )
    config.addinivalue_line(
        "markers", "compliance: marks tests that validate compliance requirements"
    )
    config.addinivalue_line(
        "markers", "e2e: marks end-to-end integration tests"
    )


def pytest_collection_modifyitems(config, items):
    """Automatically mark tests based on their location."""
    for item in items:
        # Mark tests in chaos/ directory
        if "chaos" in str(item.fspath):
            item.add_marker(pytest.mark.chaos)

        # Mark tests in performance/ directory
        if "performance" in str(item.fspath):
            item.add_marker(pytest.mark.performance)
            item.add_marker(pytest.mark.slow)

        # Mark scenario tests as e2e
        if "scenarios" in str(item.fspath) or "test_comprehensive" in str(item.fspath):
            item.add_marker(pytest.mark.e2e)
