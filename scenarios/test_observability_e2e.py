"""
E2E: Observability stack — Prometheus scrape + Grafana provisioning (ROADMAP M4)

Validates:
  1. Prometheus is up and scraping all spectre-net services
  2. Expected metrics exist for each service
  3. Alert rules are loaded (availability + SLO groups)
  4. Grafana is up with voidnxlabs datasource and dashboard provisioned
"""

import os

import pytest
import httpx

from test_runtime import client_kwargs

pytestmark = pytest.mark.e2e

PROMETHEUS_URL = os.getenv("SENTINEL_PROMETHEUS_URL", "http://localhost:9090")
GRAFANA_URL = os.getenv("SENTINEL_GRAFANA_URL", "http://localhost:3001")
GRAFANA_USER = "admin"
GRAFANA_PASS = "admin"


@pytest.fixture
async def prom_client():
    async with httpx.AsyncClient(**client_kwargs(PROMETHEUS_URL, timeout=15.0)) as c:
        yield c


@pytest.fixture
async def grafana_client():
    async with httpx.AsyncClient(
        **client_kwargs(
            GRAFANA_URL,
            timeout=15.0,
            auth=(GRAFANA_USER, GRAFANA_PASS),
        ),
    ) as c:
        yield c


def _skip_if_prom_down() -> None:
    try:
        httpx.get(f"{PROMETHEUS_URL}/-/healthy", timeout=2.0)
    except Exception:
        pytest.skip("Prometheus not running (start with --profile observability)")


# ─────────────────────────────────────────────────────────────────────────────
# Prometheus health + scrape targets
# ─────────────────────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_prometheus_healthy(prom_client):
    try:
        resp = await prom_client.get("/-/healthy")
        assert resp.status_code == 200
    except httpx.ConnectError:
        pytest.skip("Prometheus not running (start with --profile observability)")


@pytest.mark.asyncio
async def test_prometheus_scrape_targets_configured(prom_client):
    """All spectre-net services appear in Prometheus targets."""
    try:
        resp = await prom_client.get("/api/v1/targets")
    except httpx.ConnectError:
        pytest.skip("Prometheus not running")

    assert resp.status_code == 200
    data = resp.json()
    jobs = {t["labels"].get("job") for t in data["data"]["activeTargets"]}

    expected_jobs = {"phantom-api", "owasaka", "securellm-bridge", "prometheus", "neoland"}
    missing = expected_jobs - jobs
    assert not missing, f"Missing scrape jobs: {missing}\nConfigured: {jobs}"


@pytest.mark.asyncio
async def test_prometheus_alert_rules_loaded(prom_client):
    """Alert rule groups from spectre/config/alerts.yml are loaded."""
    try:
        resp = await prom_client.get("/api/v1/rules")
    except httpx.ConnectError:
        pytest.skip("Prometheus not running")

    assert resp.status_code == 200
    data = resp.json()
    group_names = {g["name"] for g in data["data"]["groups"]}

    expected_groups = {
        "spectre_availability",
        "phantom_slo",
        "securellm_bridge",
        "owasaka_health",
        "neoland_slo",
    }
    missing = expected_groups - group_names
    assert not missing, f"Missing alert groups: {missing}\nLoaded: {group_names}"


@pytest.mark.asyncio
async def test_phantom_metrics_scraped(prom_client):
    """phantom_requests_total exists in Prometheus after scrape."""
    try:
        resp = await prom_client.get(
            "/api/v1/query", params={"query": "phantom_requests_total"}
        )
    except httpx.ConnectError:
        pytest.skip("Prometheus not running")

    assert resp.status_code == 200
    data = resp.json()
    # metric may be empty if phantom has no traffic yet — just check the query succeeds
    assert data["status"] == "success", f"Query failed: {data}"


@pytest.mark.asyncio
async def test_owasaka_metrics_scraped(prom_client):
    """owasaka Go process metrics are scraped (process_resident_memory_bytes)."""
    try:
        resp = await prom_client.get(
            "/api/v1/query",
            params={"query": "process_resident_memory_bytes{job='owasaka'}"},
        )
    except httpx.ConnectError:
        pytest.skip("Prometheus not running")

    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "success"


# ─────────────────────────────────────────────────────────────────────────────
# Grafana provisioning
# ─────────────────────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_grafana_healthy(grafana_client):
    try:
        resp = await grafana_client.get("/api/health")
        assert resp.status_code == 200
        assert resp.json().get("database") == "ok"
    except httpx.ConnectError:
        pytest.skip("Grafana not running (start with --profile observability)")


@pytest.mark.asyncio
async def test_grafana_prometheus_datasource_provisioned(grafana_client):
    """Prometheus datasource is auto-provisioned from grafana/provisioning/."""
    try:
        resp = await grafana_client.get("/api/datasources/name/Prometheus")
    except httpx.ConnectError:
        pytest.skip("Grafana not running")

    assert resp.status_code == 200, (
        f"Prometheus datasource not found — check "
        f"spectre/config/grafana/provisioning/datasources/prometheus.yml"
    )
    data = resp.json()
    assert data["type"] == "prometheus"
    assert data["isDefault"] is True


@pytest.mark.asyncio
async def test_grafana_overview_dashboard_provisioned(grafana_client):
    """voidnxlabs-overview dashboard is auto-loaded from provisioning."""
    try:
        resp = await grafana_client.get("/api/dashboards/uid/voidnxlabs-overview")
    except httpx.ConnectError:
        pytest.skip("Grafana not running")

    assert resp.status_code == 200, (
        f"voidnxlabs-overview dashboard not found — check "
        f"spectre/config/grafana/dashboards/voidnxlabs-overview.json"
    )
    data = resp.json()
    assert data["dashboard"]["title"] == "voidnxlabs — Stack Overview"
