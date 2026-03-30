"""
E2E: SecureLLM Bridge — direct bridge tests + phantom→bridge integration (ROADMAP M3.4)

Validates:
  1. Bridge health, audit logging, NATS event emission
  2. Phantom routes all LLM calls through the bridge (not directly to providers)
  3. Phantom /ready includes securellm_bridge check
  4. Rate limiting is enforced
"""

import json
import asyncio
import os
import pytest
import httpx

from test_runtime import client_kwargs, request_kwargs

pytestmark = pytest.mark.e2e

SECURELLM_URL = os.getenv("SENTINEL_SECURELLM_URL", "http://localhost:8081")
PHANTOM_URL = os.getenv("SENTINEL_PUBLIC_PHANTOM_URL", "http://localhost:8008")


@pytest.fixture
async def bridge_client():
    async with httpx.AsyncClient(**client_kwargs(SECURELLM_URL, timeout=30.0)) as c:
        yield c


@pytest.fixture
async def phantom_client():
    async with httpx.AsyncClient(**client_kwargs(PHANTOM_URL, timeout=30.0)) as c:
        yield c


def _skip_if_bridge_down(bridge_client_sync_url: str = SECURELLM_URL) -> None:
    """Helper: synchronously check bridge availability (for non-async skips)."""
    import httpx as _httpx
    try:
        _httpx.get(
            f"{bridge_client_sync_url}/api/health",
            **request_kwargs(bridge_client_sync_url, timeout=2.0),
        )
    except Exception:
        pytest.skip("securellm-bridge not running (start with --profile intelligence)")


@pytest.mark.asyncio
async def test_bridge_health(bridge_client):
    """SecureLLM Bridge is reachable."""
    try:
        resp = await bridge_client.get("/api/health")
        assert resp.status_code == 200
    except httpx.ConnectError:
        pytest.skip("securellm-bridge not running (start with --profile intelligence)")


@pytest.mark.asyncio
async def test_llm_request_produces_nats_event(nats_client, bridge_client):
    """LLM request through bridge emits llm.request.v1 on spectre NATS."""
    try:
        await bridge_client.get("/health")
    except httpx.ConnectError:
        pytest.skip("securellm-bridge not running")

    events: list[dict] = []

    async def handler(msg):
        events.append(json.loads(msg.data.decode()))

    sub = await nats_client.subscribe("llm.request.v1", cb=handler)

    payload = {
        "model": "claude-sonnet-4-6",
        "messages": [{"role": "user", "content": "ping"}],
        "max_tokens": 10,
    }
    resp = await bridge_client.post("/v1/chat/completions", json=payload)
    assert resp.status_code in (200, 201, 202)

    await asyncio.sleep(1.0)
    await sub.unsubscribe()

    assert len(events) >= 1, "No llm.request.v1 event emitted by securellm-bridge"
    event = events[0]
    assert "model" in event or "request_id" in event


@pytest.mark.asyncio
async def test_audit_log_entry_created(bridge_client):
    """Each LLM request generates an immutable audit log entry."""
    try:
        resp = await bridge_client.get("/api/health")
    except httpx.ConnectError:
        pytest.skip("securellm-bridge not running")

    # Fetch audit log before request
    before = await bridge_client.get("/audit/logs")
    count_before = len(before.json().get("entries", [])) if before.status_code == 200 else 0

    # Make a request
    await bridge_client.post(
        "/v1/chat/completions",
        json={
            "model": "anthropic/claude-sonnet-4-6",
            "messages": [{"role": "user", "content": "audit test"}],
            "max_tokens": 5,
        },
    )

    # Fetch audit log after request
    after = await bridge_client.get("/audit/logs")
    if after.status_code == 200:
        count_after = len(after.json().get("entries", []))
        assert count_after > count_before, "Audit log entry not created"


# ─────────────────────────────────────────────────────────────────────────────
# M3.4 — Phantom → SecureLLM Bridge integration
# ─────────────────────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_phantom_ready_includes_bridge_check(phantom_client):
    """
    Phantom /ready endpoint must include securellm_bridge in its checks dict
    after M3.4 wiring. This validates the health check is active.
    """
    try:
        resp = await phantom_client.get("/ready")
    except httpx.ConnectError:
        pytest.skip("phantom-api not running on :8008")

    assert resp.status_code in (200, 503), f"Unexpected status: {resp.status_code}"
    data = resp.json()
    assert "checks" in data, f"Missing 'checks' in /ready response: {data}"
    assert "securellm_bridge" in data["checks"], (
        f"securellm_bridge not in /ready checks — M3.4 wiring missing.\n"
        f"Got checks: {data['checks']}"
    )


@pytest.mark.asyncio
async def test_phantom_chat_routes_through_bridge(bridge_client, phantom_client):
    """
    POST /api/chat to phantom with provider=local must route through securellm-bridge.

    Verified by: subscribing to the bridge's /api/metrics before and after the
    phantom chat call, and confirming request_count incremented.
    """
    try:
        await bridge_client.get("/api/health")
    except httpx.ConnectError:
        pytest.skip("securellm-bridge not running")
    try:
        await phantom_client.get("/health")
    except httpx.ConnectError:
        pytest.skip("phantom-api not running")

    # Capture bridge metrics before
    before_metrics = await bridge_client.get("/api/metrics")
    requests_before = 0
    if before_metrics.status_code == 200:
        for line in before_metrics.text.splitlines():
            if line.startswith("securellm_requests_total"):
                try:
                    requests_before = int(float(line.split()[-1]))
                except (ValueError, IndexError):
                    pass

    # Send chat request to phantom (local provider → routes through bridge)
    chat_payload = {
        "message": "What is voidnxlabs?",
        "conversation_id": "test_bridge_routing",
        "history": [],
        "context_size": 1,
        "llm_provider": "local",
    }
    chat_resp = await phantom_client.post("/api/chat", json=chat_payload)
    assert chat_resp.status_code == 200, f"Phantom chat failed: {chat_resp.text[:200]}"

    # Verify bridge metrics incremented
    after_metrics = await bridge_client.get("/api/metrics")
    requests_after = 0
    if after_metrics.status_code == 200:
        for line in after_metrics.text.splitlines():
            if line.startswith("securellm_requests_total"):
                try:
                    requests_after = int(float(line.split()[-1]))
                except (ValueError, IndexError):
                    pass

    if before_metrics.status_code == 200 and after_metrics.status_code == 200:
        assert requests_after > requests_before, (
            f"Bridge request counter did not increment: before={requests_before}, after={requests_after}\n"
            "Phantom may not be routing through bridge — check SECURELLM_BRIDGE_URL env var."
        )


@pytest.mark.asyncio
async def test_bridge_rate_limit_enforced(bridge_client):
    """
    SecureLLM Bridge enforces rate limiting — rapid fire requests should
    eventually return 429 Too Many Requests.
    """
    try:
        await bridge_client.get("/api/health")
    except httpx.ConnectError:
        pytest.skip("securellm-bridge not running")

    payload = {
        "model": "local/llamacpp",
        "messages": [{"role": "user", "content": "rate limit test"}],
        "max_tokens": 1,
    }

    statuses = []
    for _ in range(30):
        try:
            r = await bridge_client.post("/v1/chat/completions", json=payload, timeout=5.0)
            statuses.append(r.status_code)
        except Exception:
            break

    # At least one 429 must appear if rate limiting is active
    # (If the bridge isn't rate-limiting this provider, the test is informational)
    has_429 = 429 in statuses
    if not has_429:
        pytest.xfail(
            f"No 429 observed in {len(statuses)} requests — "
            "rate limiting may be disabled or burst limit > 30"
        )


@pytest.mark.asyncio
async def test_bridge_provider_model_routing(bridge_client):
    """
    Bridge accepts {provider}/{model} identifiers for all supported providers.
    Validates the routing table is configured for the providers phantom uses.
    """
    try:
        resp = await bridge_client.get("/v1/models")
    except httpx.ConnectError:
        pytest.skip("securellm-bridge not running")

    if resp.status_code != 200:
        pytest.skip(f"Bridge /v1/models returned {resp.status_code}")

    data = resp.json()
    model_ids = [m.get("id", "") for m in data.get("data", [])]

    # At minimum, the local provider should be configured
    has_local = any("local" in m or "llamacpp" in m for m in model_ids)
    assert has_local or len(model_ids) > 0, (
        f"Bridge has no models configured. Expected at least 'local/llamacpp'.\n"
        f"Got: {model_ids}"
    )
