"""
Chaos: Phantom degraded mode
When phantom-api is down, cerebro still serves cached responses.
"""

import time
import subprocess
import pytest
import httpx

pytestmark = pytest.mark.chaos


def _docker_compose(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["docker", "compose", "-f", "../docker-compose.yml"] + args,
        capture_output=True,
        text=True,
    )


def _cerebro_healthy() -> bool:
    try:
        resp = httpx.get("http://localhost:8002/health", timeout=3.0)
        return resp.status_code == 200
    except Exception:
        return False


def _phantom_healthy() -> bool:
    try:
        resp = httpx.get("http://localhost:8008/health", timeout=3.0)
        return resp.status_code == 200
    except Exception:
        return False


@pytest.mark.slow
def test_cerebro_serves_while_phantom_down():
    """Cerebro health and search remain available when phantom-api is stopped."""
    if not _cerebro_healthy():
        pytest.skip("cerebro not running (start with --profile intelligence)")

    assert _phantom_healthy(), "phantom must be healthy before chaos test"

    _docker_compose(["stop", "phantom-api"])
    time.sleep(3)

    assert not _phantom_healthy(), "phantom should be down"
    assert _cerebro_healthy(), "cerebro must stay up when phantom is down"

    # Cerebro search should still respond
    try:
        resp = httpx.get(
            "http://localhost:8002/search",
            params={"q": "test query"},
            timeout=10.0,
        )
        # Accept any non-5xx response — even 404 means cerebro is alive
        assert resp.status_code < 500, f"cerebro returned server error: {resp.status_code}"
    finally:
        _docker_compose(["start", "phantom-api"])

        deadline = time.time() + 30
        while time.time() < deadline:
            if _phantom_healthy():
                break
            time.sleep(1)


@pytest.mark.slow
def test_phantom_recovers_after_restart():
    """phantom-api becomes healthy again within 30s of restart."""
    assert _phantom_healthy()

    _docker_compose(["restart", "phantom-api"])

    deadline = time.time() + 30
    while time.time() < deadline:
        if _phantom_healthy():
            return
        time.sleep(1)

    pytest.fail("phantom-api did not recover within 30s of restart")
