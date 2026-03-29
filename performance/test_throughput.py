"""
Performance: Sustained throughput SLOs
≥20 req/s under concurrent load (ROADMAP 7.3)
"""

import time
import asyncio
import statistics
import pytest
import httpx

pytestmark = [pytest.mark.performance, pytest.mark.slow]

PHANTOM_URL = "http://localhost:8008"
TARGET_RPS = 20
DURATION_SECONDS = 10
CONCURRENCY = 20
P95_THRESHOLD_MS = 1000


@pytest.mark.asyncio
async def test_sustained_throughput_20rps():
    """phantom-api sustains ≥20 req/s for 10s under 20 concurrent clients."""
    async with httpx.AsyncClient(base_url=PHANTOM_URL, timeout=30.0) as client:
        try:
            await client.get("/health")
        except httpx.ConnectError:
            pytest.skip("phantom-api not running")

    results: list[tuple[float, int]] = []  # (elapsed_ms, status_code)
    errors = 0

    async def worker():
        nonlocal errors
        async with httpx.AsyncClient(base_url=PHANTOM_URL, timeout=30.0) as c:
            deadline = time.time() + DURATION_SECONDS
            while time.time() < deadline:
                try:
                    start = time.perf_counter()
                    resp = await c.post(
                        "/api/chat",
                        json={"message": "throughput test", "stream": False},
                    )
                    elapsed_ms = (time.perf_counter() - start) * 1000
                    results.append((elapsed_ms, resp.status_code))
                except Exception:
                    errors += 1

    start_wall = time.time()
    await asyncio.gather(*[worker() for _ in range(CONCURRENCY)])
    elapsed_wall = time.time() - start_wall

    total_requests = len(results)
    successful = [r for r in results if r[1] in (200, 201)]
    actual_rps = total_requests / elapsed_wall
    success_rate = len(successful) / total_requests if total_requests > 0 else 0

    latencies = sorted([r[0] for r in successful])
    p95_index = int(len(latencies) * 0.95)
    p95 = latencies[min(p95_index, len(latencies) - 1)] if latencies else float("inf")
    median = statistics.median(latencies) if latencies else float("inf")

    print(f"\nThroughput stats:")
    print(f"  Duration:      {elapsed_wall:.1f}s")
    print(f"  Total req:     {total_requests}")
    print(f"  Actual RPS:    {actual_rps:.1f}")
    print(f"  Success rate:  {success_rate:.1%}")
    print(f"  Median:        {median:.0f}ms")
    print(f"  P95:           {p95:.0f}ms")
    print(f"  Errors:        {errors}")

    assert actual_rps >= TARGET_RPS, (
        f"Throughput SLO violated: {actual_rps:.1f} RPS < {TARGET_RPS} RPS"
    )
    assert success_rate >= 0.99, (
        f"Success rate too low under load: {success_rate:.1%}"
    )
    assert p95 < P95_THRESHOLD_MS, (
        f"P95 SLO violated under load: {p95:.0f}ms > {P95_THRESHOLD_MS}ms"
    )


@pytest.mark.asyncio
async def test_concurrent_connections_stability():
    """50 simultaneous connections complete without connection errors."""
    errors = 0

    async def single_request():
        nonlocal errors
        async with httpx.AsyncClient(base_url=PHANTOM_URL, timeout=30.0) as c:
            try:
                resp = await c.post(
                    "/api/chat",
                    json={"message": "concurrent test", "stream": False},
                )
                if resp.status_code not in (200, 201):
                    errors += 1
            except Exception:
                errors += 1

    try:
        async with httpx.AsyncClient(base_url=PHANTOM_URL, timeout=5.0) as probe:
            await probe.get("/health")
    except httpx.ConnectError:
        pytest.skip("phantom-api not running")

    await asyncio.gather(*[single_request() for _ in range(50)])

    error_rate = errors / 50
    assert error_rate < 0.02, f"Too many errors under concurrent load: {errors}/50"
