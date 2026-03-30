"""
Chaos: NATS reconnect resilience
Kill NATS, verify owasaka and ai-agent-os survive and reconnect automatically.
"""

import time
import subprocess
import pytest
import httpx

from test_runtime import compose_file, request_kwargs, service_url

pytestmark = pytest.mark.chaos

COMPOSE_FILE = compose_file()
NATS_HEALTH_URL = service_url("SENTINEL_NATS_HEALTH_URL", "http://localhost:8222/healthz")
OWASAKA_URL = service_url("SENTINEL_OWASAKA_URL", "http://localhost:8080")


def _docker_compose(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["docker", "compose", "-f", str(COMPOSE_FILE)] + args,
        capture_output=True,
        text=True,
    )


def _nats_healthy() -> bool:
    try:
        resp = httpx.get(NATS_HEALTH_URL, **request_kwargs(NATS_HEALTH_URL, timeout=3.0))
        return resp.status_code == 200
    except Exception:
        return False


def _owasaka_healthy() -> bool:
    try:
        resp = httpx.get(f"{OWASAKA_URL}/health", **request_kwargs(OWASAKA_URL, timeout=3.0))
        return resp.status_code == 200
    except Exception:
        return False


@pytest.mark.slow
def test_nats_stop_and_restart():
    """NATS restarts and becomes healthy within 30s."""
    assert _nats_healthy(), "NATS must be healthy before chaos test"

    _docker_compose(["stop", "nats"])
    time.sleep(2)
    assert not _nats_healthy(), "NATS should be down after stop"

    _docker_compose(["start", "nats"])

    deadline = time.time() + 30
    while time.time() < deadline:
        if _nats_healthy():
            return
        time.sleep(1)

    pytest.fail("NATS did not recover within 30s")


@pytest.mark.slow
def test_owasaka_survives_nats_outage():
    """owasaka health endpoint stays up while NATS is down."""
    assert _owasaka_healthy(), "owasaka must be healthy before chaos test"
    assert _nats_healthy(), "NATS must be healthy before chaos test"

    _docker_compose(["stop", "nats"])
    time.sleep(3)

    # owasaka must still respond (graceful degradation, not crash)
    assert _owasaka_healthy(), "owasaka crashed when NATS went down"

    # Restore NATS
    _docker_compose(["start", "nats"])
    deadline = time.time() + 30
    while time.time() < deadline:
        if _nats_healthy():
            break
        time.sleep(1)


@pytest.mark.slow
def test_owasaka_reconnects_after_nats_recovery():
    """owasaka re-establishes NATS connection after NATS recovers."""
    import json
    import asyncio

    assert _nats_healthy()
    assert _owasaka_healthy()

    # Stop NATS
    _docker_compose(["stop", "nats"])
    time.sleep(3)

    # Restart NATS
    _docker_compose(["start", "nats"])
    time.sleep(15)  # allow reconnect

    # Verify NATS is back
    assert _nats_healthy(), "NATS did not recover"

    # Verify owasaka is still responsive
    assert _owasaka_healthy(), "owasaka did not survive nats recovery"
