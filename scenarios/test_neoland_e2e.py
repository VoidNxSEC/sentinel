"""
E2E: Neoland AI agent platform — Ciclo 1 validation suite

Validates the full neoland stack observable from the outside:
  1. Control plane health + Prometheus metrics endpoint
  2. Agent pipeline metrics appear in Prometheus after a task run
  3. NATS subjects published by neoland are routable on spectre-net
  4. adr-ledger Merkle chain metrics are exported
  5. Observability integration: neoland appears in Prometheus scrape targets

Env vars:
  NEOLAND_URL          (default: http://localhost:3002)
  NEOLAND_API_KEY      (required for task endpoint)
  SENTINEL_PROMETHEUS_URL (default: http://localhost:9090)
  NATS_URL             (default: nats://localhost:4222)
"""

import asyncio
import json
import os
import time

import httpx
import pytest

from test_runtime import client_kwargs

pytestmark = pytest.mark.e2e

NEOLAND_URL = os.getenv("NEOLAND_URL", "http://localhost:3002")
PROMETHEUS_URL = os.getenv("SENTINEL_PROMETHEUS_URL", "http://localhost:9090")
NATS_URL = os.getenv("NATS_URL", "nats://localhost:4222")
NEOLAND_API_KEY = os.getenv("NEOLAND_API_KEY", "")


# ─────────────────────────────────────────────────────────────────────────────
# Fixtures
# ─────────────────────────────────────────────────────────────────────────────


@pytest.fixture
async def neoland_client():
    headers = {"X-API-Key": NEOLAND_API_KEY} if NEOLAND_API_KEY else {}
    async with httpx.AsyncClient(
        **client_kwargs(NEOLAND_URL, timeout=30.0), headers=headers
    ) as c:
        yield c


@pytest.fixture
async def prom_client():
    async with httpx.AsyncClient(
        **client_kwargs(PROMETHEUS_URL, timeout=15.0)
    ) as c:
        yield c


def _skip_if_neoland_down() -> None:
    try:
        httpx.get(f"{NEOLAND_URL}/health", timeout=2.0)
    except Exception:
        pytest.skip("Neoland control plane not running — start with neoland-server")


def _skip_if_prom_down() -> None:
    try:
        httpx.get(f"{PROMETHEUS_URL}/-/healthy", timeout=2.0)
    except Exception:
        pytest.skip("Prometheus not running")


# ─────────────────────────────────────────────────────────────────────────────
# 1. Control plane health
# ─────────────────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_neoland_health_endpoint(neoland_client):
    """Control plane /health responds 200."""
    _skip_if_neoland_down()
    resp = await neoland_client.get("/health")
    assert resp.status_code == 200
    data = resp.json()
    assert "status" in data or resp.status_code == 200


@pytest.mark.asyncio
async def test_neoland_metrics_endpoint_format(neoland_client):
    """GET /metrics returns Prometheus text format with neoland_ prefix."""
    _skip_if_neoland_down()
    resp = await neoland_client.get("/metrics")
    assert resp.status_code == 200
    body = resp.text
    # Must have neoland-namespaced metrics
    assert "neoland_http_requests_total" in body
    assert "neoland_agent_pipeline_total" in body
    assert "neoland_nats_published_total" in body
    assert "neoland_ledger_chain_inserts_total" in body
    # Must be valid Prometheus text (lines starting with # HELP or metric name)
    lines = [l for l in body.splitlines() if l and not l.startswith("#")]
    assert len(lines) > 0, "No metric lines found"


# ─────────────────────────────────────────────────────────────────────────────
# 2. Prometheus scrape integration
# ─────────────────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_neoland_in_prometheus_scrape_targets(prom_client):
    """neoland job appears in Prometheus active targets."""
    _skip_if_prom_down()
    resp = await prom_client.get("/api/v1/targets")
    assert resp.status_code == 200
    data = resp.json()
    jobs = {t["labels"].get("job") for t in data["data"]["activeTargets"]}
    assert "neoland" in jobs, (
        f"neoland not in Prometheus scrape targets.\n"
        f"Active jobs: {sorted(jobs)}\n"
        f"Add neoland scrape job to spectre/config/prometheus.yml"
    )


@pytest.mark.asyncio
async def test_neoland_pipeline_metrics_in_prometheus(prom_client):
    """neoland_agent_pipeline_total metric is queryable after scrape."""
    _skip_if_prom_down()
    resp = await prom_client.get(
        "/api/v1/query",
        params={"query": "neoland_agent_pipeline_total"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "success", f"Prometheus query failed: {data}"


@pytest.mark.asyncio
async def test_neoland_alert_group_loaded(prom_client):
    """neoland_slo alert group is loaded in Prometheus."""
    _skip_if_prom_down()
    resp = await prom_client.get("/api/v1/rules")
    assert resp.status_code == 200
    data = resp.json()
    group_names = {g["name"] for g in data["data"]["groups"]}
    assert "neoland_slo" in group_names, (
        f"neoland_slo alert group not found.\n"
        f"Loaded groups: {sorted(group_names)}\n"
        f"Add alerts to spectre/config/alerts/neoland.yml"
    )


# ─────────────────────────────────────────────────────────────────────────────
# 3. NATS subjects — neoland.task.completed.v1
# ─────────────────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_neoland_task_completed_subject_routable(nats_client):
    """neoland.task.completed.v1 can be subscribed and receives valid envelope."""
    received: list[dict] = []

    async def handler(msg):
        try:
            data = json.loads(msg.data.decode())
            received.append(data)
        except Exception:
            pass

    sub = await nats_client.subscribe("neoland.task.completed.v1", cb=handler)

    # Publish a synthetic event to validate routing (not a real pipeline run)
    synthetic = {
        "event_type": "neoland.task.completed.v1",
        "payload": {
            "session_id": "00000000-0000-0000-0000-000000000001",
            "task_id": "00000000-0000-0000-0000-000000000002",
            "decision": "accepted",
            "risk_level": "low",
            "junior_confidence": 0.87,
            "adr_title": "sentinel-test-adr",
        },
    }
    await nats_client.publish(
        "neoland.task.completed.v1", json.dumps(synthetic).encode()
    )
    await asyncio.sleep(0.3)
    await sub.unsubscribe()

    assert len(received) == 1
    payload = received[0].get("payload", received[0])
    assert payload["decision"] == "accepted"
    assert "session_id" in payload


@pytest.mark.asyncio
async def test_neoland_pipeline_output_subject_routable(nats_client):
    """neoland.pipeline.output.v1 is routable (Phantom + Owasaka consume this)."""
    received: list[dict] = []

    async def handler(msg):
        try:
            received.append(json.loads(msg.data.decode()))
        except Exception:
            pass

    sub = await nats_client.subscribe("neoland.pipeline.output.v1", cb=handler)

    synthetic = {
        "event_type": "neoland.pipeline.output.v1",
        "payload": {
            "session_id": "00000000-0000-0000-0000-000000000003",
            "task_id": "00000000-0000-0000-0000-000000000004",
            "decision": "accepted",
            "risk_level": "medium",
            "junior_confidence": 0.73,
            "adr_title": "sentinel-pipeline-test",
            "hypothesis": "test hypothesis",
            "rationale": "test rationale",
            "action_items": ["item-1"],
            "unknowns": [],
        },
    }
    await nats_client.publish(
        "neoland.pipeline.output.v1", json.dumps(synthetic).encode()
    )
    await asyncio.sleep(0.3)
    await sub.unsubscribe()

    assert len(received) == 1


# ─────────────────────────────────────────────────────────────────────────────
# 4. Agent pipeline API (requires running server + LLM)
# ─────────────────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
@pytest.mark.skipif(not NEOLAND_API_KEY, reason="NEOLAND_API_KEY not set")
async def test_agent_task_endpoint_schema(neoland_client):
    """POST /v1/agents/task accepts valid payload and returns session_id."""
    _skip_if_neoland_down()
    payload = {
        "task": "Should we use PostgreSQL or SQLite for the agent session store?",
        "context": "sentinel integration test",
    }
    resp = await neoland_client.post("/v1/agents/task", json=payload, timeout=60.0)
    assert resp.status_code in (200, 202), f"Unexpected status: {resp.status_code} — {resp.text}"
    data = resp.json()
    assert "session_id" in data, f"Missing session_id in response: {data}"


@pytest.mark.asyncio
@pytest.mark.skipif(not NEOLAND_API_KEY, reason="NEOLAND_API_KEY not set")
async def test_agent_pipeline_metrics_increment_after_task(neoland_client, prom_client):
    """After a task run, neoland_agent_pipeline_total increments in Prometheus."""
    _skip_if_neoland_down()
    _skip_if_prom_down()

    # Snapshot before
    before = await prom_client.get(
        "/api/v1/query",
        params={"query": "sum(neoland_agent_pipeline_total)"},
    )
    before_val = float(
        before.json()["data"]["result"][0]["value"][1]
        if before.json()["data"]["result"]
        else 0
    )

    # Run task
    await neoland_client.post(
        "/v1/agents/task",
        json={"task": "sentinel metric increment test"},
        timeout=90.0,
    )

    # Wait for Prometheus scrape (default interval 15s)
    await asyncio.sleep(20)

    after = await prom_client.get(
        "/api/v1/query",
        params={"query": "sum(neoland_agent_pipeline_total)"},
    )
    after_val = float(
        after.json()["data"]["result"][0]["value"][1]
        if after.json()["data"]["result"]
        else 0
    )
    assert after_val > before_val, (
        f"neoland_agent_pipeline_total did not increment: {before_val} → {after_val}"
    )
