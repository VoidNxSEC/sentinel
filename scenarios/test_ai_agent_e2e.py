"""
E2E: ai-agent-os system metrics pipeline
Validates system.metrics.v1 events emitted on NATS conform to schema.
"""

import json
import asyncio
import pytest

pytestmark = pytest.mark.e2e


@pytest.mark.asyncio
async def test_metrics_schema_validation(nats_client):
    """system.metrics.v1 payload matches expected schema."""
    received: list[dict] = []

    async def handler(msg):
        received.append(json.loads(msg.data.decode()))

    sub = await nats_client.subscribe("system.metrics.v1", cb=handler)

    # Simulate an ai-agent-os bundle
    metrics = {
        "host": "nixos-sentinel",
        "timestamp": "2026-03-29T12:00:00Z",
        "cpu_percent": 38.7,
        "memory_percent": 55.2,
        "temperature_celsius": 62.0,
        "uptime_seconds": 86400,
        "load_average": [1.2, 0.9, 0.8],
    }
    await nats_client.publish("system.metrics.v1", json.dumps(metrics).encode())
    await asyncio.sleep(0.5)
    await sub.unsubscribe()

    assert len(received) == 1
    event = received[0]

    required = {"host", "timestamp", "cpu_percent", "memory_percent"}
    missing = required - event.keys()
    assert not missing, f"Missing required fields: {missing}"

    assert 0.0 <= event["cpu_percent"] <= 100.0
    assert 0.0 <= event["memory_percent"] <= 100.0


@pytest.mark.asyncio
async def test_thermal_alert_event(nats_client):
    """High-temperature metrics trigger alert-level classification."""
    received: list[dict] = []

    async def handler(msg):
        received.append(json.loads(msg.data.decode()))

    sub = await nats_client.subscribe("system.metrics.v1", cb=handler)

    critical_metrics = {
        "host": "nixos-overloaded",
        "timestamp": "2026-03-29T12:00:00Z",
        "cpu_percent": 95.0,
        "memory_percent": 91.0,
        "temperature_celsius": 84.0,  # above 80°C threshold
        "uptime_seconds": 3600,
        "alerts": [
            {"level": "critical", "type": "thermal", "value": 84.0}
        ],
    }
    await nats_client.publish("system.metrics.v1", json.dumps(critical_metrics).encode())
    await asyncio.sleep(0.5)
    await sub.unsubscribe()

    assert len(received) == 1
    event = received[0]
    assert event["temperature_celsius"] >= 80.0
    assert "alerts" in event
    assert any(a["level"] == "critical" for a in event["alerts"])


@pytest.mark.asyncio
async def test_multiple_hosts_isolated(nats_client):
    """Events from different hosts are independently routed."""
    received: list[dict] = []

    async def handler(msg):
        received.append(json.loads(msg.data.decode()))

    sub = await nats_client.subscribe("system.metrics.v1", cb=handler)

    hosts = ["host-a", "host-b", "host-c"]
    for host in hosts:
        await nats_client.publish(
            "system.metrics.v1",
            json.dumps({
                "host": host,
                "timestamp": "2026-03-29T12:00:00Z",
                "cpu_percent": 20.0,
                "memory_percent": 40.0,
                "temperature_celsius": 50.0,
            }).encode()
        )

    await asyncio.sleep(0.5)
    await sub.unsubscribe()

    assert len(received) == 3
    seen_hosts = {e["host"] for e in received}
    assert seen_hosts == set(hosts)
