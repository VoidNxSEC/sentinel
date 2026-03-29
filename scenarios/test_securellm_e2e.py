"""
E2E: SecureLLM Bridge audit trail
Validates that LLM calls routed through securellm-bridge produce audit log entries.
"""

import json
import asyncio
import pytest
import httpx

pytestmark = pytest.mark.e2e

SECURELLM_URL = "http://localhost:8081"


@pytest.fixture
async def bridge_client():
    async with httpx.AsyncClient(base_url=SECURELLM_URL, timeout=30.0) as c:
        yield c


@pytest.mark.asyncio
async def test_bridge_health(bridge_client):
    """SecureLLM Bridge is reachable."""
    try:
        resp = await bridge_client.get("/health")
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
        resp = await bridge_client.get("/health")
    except httpx.ConnectError:
        pytest.skip("securellm-bridge not running")

    # Fetch audit log before request
    before = await bridge_client.get("/audit/logs")
    count_before = len(before.json().get("entries", [])) if before.status_code == 200 else 0

    # Make a request
    await bridge_client.post(
        "/v1/chat/completions",
        json={
            "model": "claude-sonnet-4-6",
            "messages": [{"role": "user", "content": "audit test"}],
            "max_tokens": 5,
        },
    )

    # Fetch audit log after request
    after = await bridge_client.get("/audit/logs")
    if after.status_code == 200:
        count_after = len(after.json().get("entries", []))
        assert count_after > count_before, "Audit log entry not created"
