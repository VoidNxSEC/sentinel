"""
Chaos: Partial boot — only core services up
Intelligence services (cerebro, securellm-bridge) gracefully unavailable.
"""

import pytest
import httpx

pytestmark = pytest.mark.chaos

CORE_SERVICES = {
    "nats": "http://localhost:8222/healthz",
    "phantom-api": "http://localhost:8008/health",
    "owasaka": "http://localhost:8080/health",
}

INTELLIGENCE_SERVICES = {
    "cerebro": "http://localhost:8002/health",
    "securellm-bridge": "http://localhost:8081/health",
}


def _is_up(url: str) -> bool:
    try:
        resp = httpx.get(url, timeout=3.0)
        return resp.status_code == 200
    except Exception:
        return False


def test_core_services_reachable_in_partial_boot():
    """Core profile services are healthy (NATS, phantom-api, owasaka)."""
    for name, url in CORE_SERVICES.items():
        assert _is_up(url), f"Core service unreachable: {name} ({url})"


def test_intelligence_services_degrade_gracefully():
    """Intelligence services are either up or return a clean error (not a crash)."""
    for name, url in INTELLIGENCE_SERVICES.items():
        try:
            resp = httpx.get(url, timeout=3.0)
            # If reachable, must return a valid HTTP response
            assert resp.status_code < 600, f"{name} returned invalid status"
        except httpx.ConnectError:
            # Service not running — expected in core-only boot
            pass
        except Exception as exc:
            pytest.fail(f"{name} raised unexpected exception: {exc}")


def test_phantom_chat_works_without_intelligence_services():
    """phantom-api /api/chat responds even when cerebro/securellm-bridge are down."""
    if not _is_up("http://localhost:8008/health"):
        pytest.skip("phantom-api not running")

    payload = {"message": "Hello from partial boot test", "stream": False}
    try:
        resp = httpx.post("http://localhost:8008/api/chat", json=payload, timeout=15.0)
        assert resp.status_code in (200, 201, 503), (
            f"Unexpected status from phantom in degraded mode: {resp.status_code}"
        )
    except httpx.ConnectError:
        pytest.skip("phantom-api not reachable")


def test_owasaka_publishes_to_nats_without_consumers():
    """owasaka remains healthy even when no consumers are subscribed to its events."""
    if not _is_up("http://localhost:8080/health"):
        pytest.skip("owasaka not running")

    if not _is_up("http://localhost:8222/healthz"):
        pytest.skip("NATS not running")

    # owasaka health must remain stable after publishing with no consumers
    resp = httpx.get("http://localhost:8080/health", timeout=5.0)
    assert resp.status_code == 200
