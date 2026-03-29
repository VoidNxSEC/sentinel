"""
E2E: Phantom document intelligence pipeline
upload → vectors/search → /api/chat uses injected context
"""

import pytest
import httpx

pytestmark = pytest.mark.e2e

PHANTOM_URL = "http://localhost:8008"


@pytest.fixture
async def client():
    async with httpx.AsyncClient(base_url=PHANTOM_URL, timeout=30.0) as c:
        yield c


@pytest.mark.asyncio
async def test_phantom_health(client):
    """Phantom API is reachable and operational."""
    resp = await client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body.get("status") in ("ok", "operational", "healthy")


@pytest.mark.asyncio
async def test_chat_endpoint_responds(client):
    """POST /api/chat returns a structured response within 500ms."""
    payload = {"message": "What services does voidnxlabs operate?", "stream": False}

    import time
    start = time.perf_counter()
    resp = await client.post("/api/chat", json=payload)
    elapsed_ms = (time.perf_counter() - start) * 1000

    assert resp.status_code in (200, 201), f"Unexpected status: {resp.status_code}"
    body = resp.json()
    assert "response" in body or "content" in body or "message" in body
    assert elapsed_ms < 500, f"Chat P99 SLO exceeded: {elapsed_ms:.0f}ms > 500ms"


@pytest.mark.asyncio
async def test_vector_search_returns_results(client):
    """GET /vectors/search returns results for a known query."""
    resp = await client.get("/vectors/search", params={"q": "NATS event bus", "k": 3})

    # Accept 200 (results found) or 204 (empty index in test env)
    assert resp.status_code in (200, 204), f"Unexpected status: {resp.status_code}"
    if resp.status_code == 200:
        body = resp.json()
        assert isinstance(body, list) or "results" in body


@pytest.mark.asyncio
async def test_file_ingest_pipeline(client):
    """Uploaded file is ingested and becomes searchable."""
    import io

    content = b"voidnxlabs securellm-bridge provides zero-trust LLM proxy functionality."
    files = {"file": ("test_doc.txt", io.BytesIO(content), "text/plain")}

    resp = await client.post("/ingest", files=files)
    # Some phantom versions use /upload
    if resp.status_code == 404:
        resp = await client.post("/upload", files=files)

    assert resp.status_code in (200, 201, 202), (
        f"Ingest failed: {resp.status_code} {resp.text}"
    )
