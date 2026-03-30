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
import os
import subprocess
import inspect
import ssl
from pathlib import Path
from typing import Dict, Any, Callable

import pytest
import httpx
from dotenv import dotenv_values


# ========================================
# Test Configuration
# ========================================

TIMEOUT_DEFAULT = 30.0
TIMEOUT_LONG = 60.0
SERVICE_STARTUP_WAIT = 20  # seconds
SERVICE_HEALTH_CHECK_RETRIES = 30
SERVICE_HEALTH_CHECK_INTERVAL = 2  # seconds

BASE_DIR = Path(__file__).parent.resolve()
WORKSPACE_ROOT = Path(
    os.getenv("SENTINEL_WORKSPACE_ROOT", str(BASE_DIR.parent))
).resolve()
ROOT_DIR = WORKSPACE_ROOT
FIXTURES_DIR = BASE_DIR / "fixtures" / "bundles"
DOCKER_COMPOSE_FILE = Path(
    os.getenv("SENTINEL_COMPOSE_FILE", str(BASE_DIR / "docker-compose.test.yml"))
)
DEFAULT_CA_CERT_FILE = ROOT_DIR / "secrets" / "tls" / "ca.crt"
DEFAULT_ENV_FILE = Path(os.getenv("SENTINEL_ENV_FILE", str(ROOT_DIR / ".env")))
NKEYS_DIR = Path(
    os.getenv("SENTINEL_NKEYS_DIR", str(ROOT_DIR / "spectre" / "config" / "nkeys"))
)
DEFAULT_NATS_CLIENT_CERT_FILE = ROOT_DIR / "secrets" / "tls" / "phantom-api.crt"
DEFAULT_NATS_CLIENT_KEY_FILE = ROOT_DIR / "secrets" / "tls" / "phantom-api.key"


def _env_true(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _is_live_stack_mode() -> bool:
    return _env_true("SENTINEL_USE_LIVE_STACK", default=False)


def _http_verify_arg(url: str):
    if not url.startswith("https://"):
        return True
    if _env_true("SENTINEL_TLS_INSECURE", default=False):
        return False
    ca_cert = os.getenv("SENTINEL_CA_CERT")
    if ca_cert:
        return ca_cert
    if DEFAULT_CA_CERT_FILE.exists():
        return str(DEFAULT_CA_CERT_FILE)
    return True


def _load_root_env() -> dict[str, str]:
    if not DEFAULT_ENV_FILE.exists():
        return {}
    return {
        key: value
        for key, value in dotenv_values(DEFAULT_ENV_FILE).items()
        if value is not None
    }


def _get_config_value(name: str, default: str | None = None) -> str | None:
    return os.getenv(name) or _load_root_env().get(name) or default


def _require_config_value(name: str) -> str:
    value = _get_config_value(name)
    if not value:
        raise RuntimeError(f"Missing required config value: {name}")
    return value


def _nkey_seed_file_for(name: str) -> Path | None:
    mapping = {
        "OWASAKA_NKEY_SEED": "owasaka.nk",
        "AI_AGENT_OS_NKEY_SEED": "ai-agent-os.nk",
        "PHANTOM_NKEY_SEED": "phantom.nk",
        "PHANTOM_SOC_NKEY_SEED": "phantom-soc.nk",
        "CEREBRO_NKEY_SEED": "cerebro.nk",
        "SECURELLM_BRIDGE_NKEY_SEED": "securellm-bridge.nk",
    }
    filename = mapping.get(name)
    if filename is None:
        return None
    path = NKEYS_DIR / filename
    return path if path.exists() else None


def _load_nkey_seed(name: str) -> str | None:
    value = _get_config_value(name)
    if value:
        return value

    path = _nkey_seed_file_for(name)
    if path is None:
        return None

    for line in reversed(path.read_text().splitlines()):
        candidate = line.strip()
        if candidate and not candidate.startswith("#"):
            return candidate
    return None


def _require_nkey_seed(name: str) -> str:
    value = _load_nkey_seed(name)
    if not value:
        raise RuntimeError(f"Missing required NKey seed: {name}")
    return value


def _nats_auth_enabled() -> bool:
    return _load_nkey_seed("OWASAKA_NKEY_SEED") is not None


def _build_nats_tls_context() -> ssl.SSLContext:
    ca_file = _get_config_value("NATS_CA_FILE")
    cert_file = _get_config_value("NATS_CLIENT_CERT_FILE")
    key_file = _get_config_value("NATS_CLIENT_KEY_FILE")

    if not ca_file and DEFAULT_CA_CERT_FILE.exists():
        ca_file = str(DEFAULT_CA_CERT_FILE)
    if not cert_file and DEFAULT_NATS_CLIENT_CERT_FILE.exists():
        cert_file = str(DEFAULT_NATS_CLIENT_CERT_FILE)
    if not key_file and DEFAULT_NATS_CLIENT_KEY_FILE.exists():
        key_file = str(DEFAULT_NATS_CLIENT_KEY_FILE)

    tls_context = ssl.create_default_context(cafile=ca_file or None)
    if hasattr(ssl, "VERIFY_X509_STRICT"):
        tls_context.verify_flags &= ~ssl.VERIFY_X509_STRICT
    if cert_file and key_file:
        tls_context.load_cert_chain(certfile=cert_file, keyfile=key_file)
    return tls_context


# ========================================
# Session-scoped Fixtures (Run Once)
# ========================================

@pytest.fixture(scope="session")
def docker_services():
    """
    Start all services via docker-compose at the beginning of test session.
    Tear down at the end.
    """
    live_mode = _is_live_stack_mode()
    if live_mode:
        print("\n🚀 Using existing live stack (SENTINEL_USE_LIVE_STACK=1)...")
        print("🏥 Checking service health...")
        _wait_for_services()
        print("✅ Live stack ready\n")
        yield
        print("\nℹ️ Live stack mode: skipping docker-compose teardown\n")
        return

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
    if _is_live_stack_mode():
        phantom_health_url = os.getenv("SENTINEL_PHANTOM_HEALTH_URL", "https://localhost:8008/health")
    else:
        phantom_health_url = os.getenv("SENTINEL_PHANTOM_HEALTH_URL", "http://localhost:8000/health")

    services = [
        ("Phantom", phantom_health_url),
        ("NATS", os.getenv("SENTINEL_NATS_HEALTH_URL", "http://localhost:8222/healthz")),
    ]

    optional_services = []
    if not _is_live_stack_mode() or _env_true("SENTINEL_CHECK_OPTIONAL_SERVICES", default=False):
        optional_services.append(("Cerebro", "http://localhost:8002/health"))

    for name, url in services:
        _wait_for_service(name, url, required=True)

    for name, url in optional_services:
        _wait_for_service(name, url, required=False)


def _wait_for_service(name: str, url: str, required: bool = True):
    """Wait for a specific service to be healthy."""
    verify = _http_verify_arg(url)
    for attempt in range(SERVICE_HEALTH_CHECK_RETRIES):
        try:
            response = httpx.get(url, timeout=5.0, verify=verify)
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
    base_url = _get_config_value(
        "SENTINEL_PHANTOM_TEST_URL",
        "https://localhost:8008" if _is_live_stack_mode() else "http://localhost:8000",
    )
    async with httpx.AsyncClient(
        base_url=base_url,
        timeout=TIMEOUT_DEFAULT,
        verify=_http_verify_arg(base_url),
    ) as client:
        yield client


@pytest.fixture
async def cerebro_client(docker_services):
    """HTTP client for Cerebro RAG API."""
    base_url = _get_config_value("SENTINEL_CEREBRO_URL", "http://localhost:8002")
    async with httpx.AsyncClient(
        base_url=base_url,
        timeout=TIMEOUT_DEFAULT,
        verify=_http_verify_arg(base_url),
    ) as client:
        yield client


@pytest.fixture
def nats_url(docker_services) -> str:
    """NATS connection URL."""
    return os.getenv("SENTINEL_NATS_URL", "nats://localhost:4222")


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


# ========================================
# Production Stack Fixtures (port 8008)
# ========================================

@pytest.fixture
async def phantom_api_client(docker_services):
    """HTTP client for Phantom API on production port 8008."""
    base_url = _get_config_value("SENTINEL_PUBLIC_PHANTOM_URL", "http://localhost:8008")
    async with httpx.AsyncClient(
        base_url=base_url,
        timeout=TIMEOUT_DEFAULT,
        verify=_http_verify_arg(base_url),
    ) as client:
        yield client


@pytest.fixture
async def owasaka_client(docker_services):
    """HTTP client for Owasaka SIEM API."""
    base_url = _get_config_value("SENTINEL_OWASAKA_URL", "http://localhost:8080")
    async with httpx.AsyncClient(
        base_url=base_url,
        timeout=TIMEOUT_DEFAULT,
        verify=_http_verify_arg(base_url),
    ) as client:
        yield client


@pytest.fixture
async def securellm_client(docker_services):
    """HTTP client for SecureLLM Bridge (host port 8081)."""
    base_url = _get_config_value("SENTINEL_SECURELLM_URL", "http://localhost:8081")
    async with httpx.AsyncClient(
        base_url=base_url,
        timeout=TIMEOUT_DEFAULT,
        verify=_http_verify_arg(base_url),
    ) as client:
        yield client


@pytest.fixture
def ai_agent_client(nats_url) -> str:
    """NATS URL for subscribing to ai-agent-os events."""
    return nats_url


@pytest.fixture
async def nats_client(docker_services):
    """
    Auth-aware NATS test client for live publish/subscribe validation.
    """
    try:
        import nats as nats_lib
    except ImportError:
        pytest.skip("nats-py not installed — run: poetry install -E nats")

    nats_target = _get_config_value("SENTINEL_NATS_URL", "nats://localhost:4222")

    class RoutedNatsClient:
        def __init__(self, url: str):
            self.url = url
            self._clients: dict[str, Any] = {}
            self._closed = False

        async def _connect(self, role: str, seed_env: str):
            client = self._clients.get(role)
            if client is not None:
                return client

            connect_kwargs = {
                "servers": [self.url],
                "connect_timeout": 3,
                "allow_reconnect": False,
            }
            if _nats_auth_enabled():
                connect_kwargs["nkeys_seed_str"] = _require_nkey_seed(seed_env)
            if (
                self.url.startswith("tls://")
                or _get_config_value("NATS_CA_FILE")
                or _get_config_value("NATS_CLIENT_CERT_FILE")
                or _get_config_value("NATS_CLIENT_KEY_FILE")
            ):
                connect_kwargs["tls"] = _build_nats_tls_context()

            client = await nats_lib.connect(**connect_kwargs)
            self._clients[role] = client
            return client

        async def _publisher_for(self, subject: str):
            if subject.startswith("network."):
                return await self._connect("owasaka", "OWASAKA_NKEY_SEED")
            if subject.startswith("system."):
                return await self._connect("ai-agent-os", "AI_AGENT_OS_NKEY_SEED")
            if subject.startswith(("ingest.", "analysis.")):
                return await self._connect("phantom", "PHANTOM_NKEY_SEED")
            if subject.startswith("cognition."):
                return await self._connect("cerebro", "CEREBRO_NKEY_SEED")
            if subject.startswith("llm."):
                return await self._connect("securellm-bridge", "SECURELLM_BRIDGE_NKEY_SEED")
            raise RuntimeError(f"No publisher mapping configured for subject: {subject}")

        async def _subscriber_for(self, subject: str):
            if subject.startswith(("network.", "system.")):
                return await self._connect("phantom-soc", "PHANTOM_SOC_NKEY_SEED")
            if subject.startswith(("ingest.", "analysis.")):
                return await self._connect("cerebro", "CEREBRO_NKEY_SEED")
            if subject.startswith("cognition."):
                return await self._connect("phantom", "PHANTOM_NKEY_SEED")
            if subject.startswith("llm."):
                return await self._connect("securellm-bridge", "SECURELLM_BRIDGE_NKEY_SEED")
            raise RuntimeError(f"No subscriber mapping configured for subject: {subject}")

        async def subscribe(self, subject: str, **kwargs):
            client = await self._subscriber_for(subject)
            callback = kwargs.get("cb")
            if callback is not None and not inspect.iscoroutinefunction(callback):
                async def _async_callback(message):
                    callback(message)
                kwargs["cb"] = _async_callback
            return await client.subscribe(subject, **kwargs)

        async def publish(self, subject: str, payload: bytes, **kwargs):
            client = await self._publisher_for(subject)
            return await client.publish(subject, payload, **kwargs)

        async def flush(self):
            for client in self._clients.values():
                await client.flush()

        async def drain(self):
            if self._closed:
                return
            self._closed = True
            for client in self._clients.values():
                await client.drain()

    nc = RoutedNatsClient(nats_target)
    yield nc
    await nc.drain()
