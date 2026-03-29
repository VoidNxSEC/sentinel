"""
E2E: Spectre event bus routing
Validates NATS subject schema and pub/sub delivery across spectre-net.
"""

import json
import asyncio
import pytest

pytestmark = pytest.mark.e2e


@pytest.mark.asyncio
async def test_event_delivery_roundtrip(nats_client):
    """Published events are delivered to subscribers within 500ms."""
    received: list[dict] = []

    async def handler(msg):
        received.append(json.loads(msg.data.decode()))

    sub = await nats_client.subscribe("network.asset.discovered.v1", cb=handler)

    payload = {
        "ip": "192.168.1.100",
        "hostname": "test-host",
        "mac": "aa:bb:cc:dd:ee:ff",
        "services": ["ssh", "http"],
        "source": "owasaka",
    }
    await nats_client.publish(
        "network.asset.discovered.v1", json.dumps(payload).encode()
    )
    await asyncio.sleep(0.5)
    await sub.unsubscribe()

    assert len(received) == 1
    assert received[0]["ip"] == "192.168.1.100"
    assert received[0]["source"] == "owasaka"


@pytest.mark.asyncio
async def test_event_subject_schema(nats_client):
    """All registered subjects conform to {domain}.{entity}.{action}.v{version}."""
    subjects = [
        "network.asset.discovered.v1",
        "network.dns.query.v1",
        "network.dns.threat.v1",
        "network.service.detected.v1",
        "network.topology.updated.v1",
        "system.metrics.v1",
        "ingest.file.created.v1",
        "ingest.file.sanitized.v1",
        "cognition.query.received.v1",
        "cognition.insight.generated.v1",
        "llm.request.v1",
        "llm.response.v1",
        "analysis.request.v1",
        "analysis.response.v1",
    ]
    for subject in subjects:
        parts = subject.split(".")
        assert len(parts) == 4, f"Bad subject format: {subject}"
        assert parts[3].startswith("v"), f"Version must start with 'v': {subject}"
        assert parts[3][1:].isdigit(), f"Version must be numeric: {subject}"


@pytest.mark.asyncio
async def test_system_metrics_schema(nats_client):
    """system.metrics.v1 events contain required ai-agent-os fields."""
    received: list[dict] = []

    async def handler(msg):
        received.append(json.loads(msg.data.decode()))

    sub = await nats_client.subscribe("system.metrics.v1", cb=handler)

    payload = {
        "host": "nixos-dev",
        "timestamp": "2026-03-29T00:00:00Z",
        "cpu_percent": 45.2,
        "memory_percent": 62.1,
        "temperature_celsius": 58.0,
    }
    await nats_client.publish("system.metrics.v1", json.dumps(payload).encode())
    await asyncio.sleep(0.5)
    await sub.unsubscribe()

    assert len(received) == 1
    event = received[0]
    required_fields = {"host", "timestamp", "cpu_percent", "memory_percent"}
    assert required_fields.issubset(event.keys()), (
        f"Missing fields: {required_fields - event.keys()}"
    )


@pytest.mark.asyncio
async def test_multiple_subscribers(nats_client):
    """Multiple subscribers on the same subject each receive the event."""
    inbox_a: list[bytes] = []
    inbox_b: list[bytes] = []

    sub_a = await nats_client.subscribe(
        "network.dns.query.v1", cb=lambda m: inbox_a.append(m.data)
    )
    sub_b = await nats_client.subscribe(
        "network.dns.query.v1", cb=lambda m: inbox_b.append(m.data)
    )

    await nats_client.publish(
        "network.dns.query.v1", b'{"query":"example.com","type":"A"}'
    )
    await asyncio.sleep(0.5)

    await sub_a.unsubscribe()
    await sub_b.unsubscribe()

    assert len(inbox_a) == 1
    assert len(inbox_b) == 1
