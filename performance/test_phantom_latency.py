"""
Performance: Phantom API latency SLOs
P99 < 500ms for /api/chat (ROADMAP 7.3)
"""

import time
import asyncio
import statistics
import pytest
import httpx

pytestmark = [pytest.mark.performance, pytest.mark.slow]

PHANTOM_URL = "http://localhost:8008"
SAMPLE_SIZE = 20
P99_THRESHOLD_MS = 500
P95_THRESHOLD_MS = 350


async def _chat_request(client: httpx.AsyncClient) -> float:
    start = time.perf_counter()
    resp = await client.post(
        "/api/chat",
        json={"message": "What is NATS?", "stream": False},
    )
    elapsed_ms = (time.perf_counter() - start) * 1000
    assert resp.status_code in (200, 201), f"Unexpected status: {resp.status_code}"
    return elapsed_ms


@pytest.mark.asyncio
async def test_chat_p99_latency():
    """P99 latency for /api/chat is below 500ms."""
    async with httpx.AsyncClient(base_url=PHANTOM_URL, timeout=30.0) as client:
        try:
            await client.get("/health")
        except httpx.ConnectError:
            pytest.skip("phantom-api not running")

        latencies = []
        for _ in range(SAMPLE_SIZE):
            latencies.append(await _chat_request(client))

    latencies.sort()
    p99_index = int(len(latencies) * 0.99)
    p95_index = int(len(latencies) * 0.95)
    p99 = latencies[min(p99_index, len(latencies) - 1)]
    p95 = latencies[min(p95_index, len(latencies) - 1)]
    median = statistics.median(latencies)

    print(f"\nLatency stats (n={SAMPLE_SIZE}):")
    print(f"  Median: {median:.0f}ms")
    print(f"  P95:    {p95:.0f}ms")
    print(f"  P99:    {p99:.0f}ms")

    assert p99 < P99_THRESHOLD_MS, f"P99 SLO violated: {p99:.0f}ms > {P99_THRESHOLD_MS}ms"
    assert p95 < P95_THRESHOLD_MS, f"P95 SLO violated: {p95:.0f}ms > {P95_THRESHOLD_MS}ms"


@pytest.mark.asyncio
async def test_chat_cold_start_latency():
    """First request after service start completes within 2s."""
    async with httpx.AsyncClient(base_url=PHANTOM_URL, timeout=30.0) as client:
        try:
            await client.get("/health")
        except httpx.ConnectError:
            pytest.skip("phantom-api not running")

        elapsed_ms = await _chat_request(client)
        assert elapsed_ms < 2000, f"Cold start exceeded 2s: {elapsed_ms:.0f}ms"


@pytest.mark.asyncio
async def test_health_endpoint_latency():
    """GET /health responds within 50ms (lightweight liveness probe)."""
    async with httpx.AsyncClient(base_url=PHANTOM_URL, timeout=5.0) as client:
        try:
            start = time.perf_counter()
            resp = await client.get("/health")
            elapsed_ms = (time.perf_counter() - start) * 1000
        except httpx.ConnectError:
            pytest.skip("phantom-api not running")

        assert resp.status_code == 200
        assert elapsed_ms < 50, f"Health check too slow: {elapsed_ms:.0f}ms > 50ms"
