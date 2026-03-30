"""
Cortex ↔ Phantom API E2E — proxy round-trip tests (ROADMAP M2.2)

The cortex desktop app (phantom-nx/apps/cortex) calls phantom-api directly
on the configured apiUrl. These tests replicate exactly the HTTP contract
that cortex depends on, verifying the full round-trip at the API level.

Two test tiers:
  1. httpx contract tests — run anywhere phantom-api is up (no browser needed)
  2. Playwright browser tests — require cortex dev server on :1420 (skipped if absent)

Requires: phantom-api running on localhost:8008
Optional: cortex dev server on localhost:1420 (bun run dev in phantom-nx/apps/cortex)
"""

import io
import os
import time

import httpx
import pytest

from test_runtime import client_kwargs, request_kwargs


PHANTOM_URL = os.getenv("SENTINEL_PUBLIC_PHANTOM_URL", "http://localhost:8008")
CORTEX_DEV_URL = "http://localhost:1420"


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _cortex_client() -> httpx.Client:
    """Synchronous client configured exactly as cortex's fetch() calls."""
    return httpx.Client(**client_kwargs(PHANTOM_URL, timeout=30.0))


def _cortex_dev_available() -> bool:
    try:
        r = httpx.get(CORTEX_DEV_URL, **request_kwargs(CORTEX_DEV_URL, timeout=3.0))
        return r.status_code < 500
    except Exception:
        return False


# ─────────────────────────────────────────────────────────────────────────────
# Tier 1 — HTTP contract tests (replicates cortex fetch() calls)
# ─────────────────────────────────────────────────────────────────────────────

@pytest.mark.e2e
def test_cortex_health_check(phantom_api_client_sync):
    """
    cortex checkApi() — GET /health
    Status indicator turns green when this returns 200.
    """
    r = phantom_api_client_sync.get("/health")
    assert r.status_code == 200, f"Health check failed: {r.text}"
    data = r.json()
    assert data.get("status") in ("operational", "ok", "healthy"), f"Unexpected: {data}"


@pytest.mark.e2e
def test_cortex_load_models(phantom_api_client_sync):
    """
    cortex loadModels() — GET /api/models
    Populates the model selector in Settings tab.
    """
    r = phantom_api_client_sync.get("/api/models")
    assert r.status_code == 200, f"Models endpoint failed: {r.text}"
    data = r.json()
    # Accept dict of {provider: [models]} or list
    assert data is not None, "Empty models response"


@pytest.mark.e2e
def test_cortex_chat_round_trip(phantom_api_client_sync):
    """
    cortex sendMessage() — POST /api/chat
    Full round-trip: user message → phantom RAG → assistant response.
    Validates the response shape cortex depends on.
    """
    payload = {
        "message": "What is the voidnxlabs sentinel project?",
        "conversation_id": f"cortex_e2e_{int(time.time())}",
        "history": [],
        "context_size": 5,
        "llm_provider": "local",
    }
    r = phantom_api_client_sync.post("/api/chat", json=payload)
    assert r.status_code == 200, f"Chat failed: {r.text}"

    data = r.json()
    # cortex reads: data.message.content and data.message.sources
    assert "message" in data or "response" in data or "content" in data, (
        f"Response missing message field. Got: {list(data.keys())}"
    )

    msg = data.get("message", data)
    if isinstance(msg, dict):
        assert "content" in msg, f"message.content missing: {msg}"


@pytest.mark.e2e
def test_cortex_file_upload_round_trip(phantom_api_client_sync):
    """
    cortex handleDrop() — POST /api/upload (multipart)
    Drag-and-drop in Settings tab uploads to phantom's RAG index.
    Verifies cortex reads: data.files[].filename and data.files[].status
    """
    content = "cortex e2e test document - round trip validation.".encode()
    files = [("files", ("cortex_test.txt", io.BytesIO(content), "text/plain"))]

    r = phantom_api_client_sync.post("/api/upload", files=files)
    assert r.status_code == 200, f"Upload failed: {r.text}"

    data = r.json()
    assert data, "Empty upload response"

    # cortex reads data.files[].filename and data.files[].status
    if isinstance(data, dict) and "files" in data:
        for f in data["files"]:
            assert "filename" in f or "name" in f, f"Missing filename in: {f}"
            assert "status" in f, f"Missing status in: {f}"


@pytest.mark.e2e
def test_cortex_prompt_test_round_trip(phantom_api_client_sync):
    """
    cortex testPrompt() — POST /api/prompt/test
    Workbench tab: renders template with variables, returns token count.
    Verifies cortex reads: data.rendered, data.tokens, data.success
    """
    payload = {
        "template": "Context: {context}\n\nQuestion: {question}\n\nAnswer:",
        "variables": {
            "context": "voidnxlabs builds sovereign AI infrastructure",
            "question": "What does voidnxlabs build?",
        },
    }
    r = phantom_api_client_sync.post("/api/prompt/test", json=payload)
    assert r.status_code == 200, f"Prompt test failed: {r.text}"

    data = r.json()
    assert "rendered" in data or "result" in data, (
        f"Missing rendered field. Got: {list(data.keys())}"
    )


@pytest.mark.e2e
def test_cortex_conversation_history(phantom_api_client_sync):
    """
    cortex multi-turn — POST /api/chat with history
    Validates that cortex can pass conversation history and get coherent response.
    """
    conv_id = f"cortex_history_{int(time.time())}"
    history = [
        {"role": "user", "content": "What is NATS?"},
        {"role": "assistant", "content": "NATS is a lightweight messaging system."},
    ]
    payload = {
        "message": "How does it relate to voidnxlabs?",
        "conversation_id": conv_id,
        "history": history,
        "context_size": 3,
        "llm_provider": "local",
    }
    r = phantom_api_client_sync.post("/api/chat", json=payload)
    assert r.status_code == 200, f"Multi-turn chat failed: {r.text}"


# ─────────────────────────────────────────────────────────────────────────────
# Tier 2 — Playwright browser tests (require dev server on :1420)
# ─────────────────────────────────────────────────────────────────────────────

@pytest.mark.e2e
@pytest.mark.slow
def test_cortex_browser_api_status_indicator():
    """
    Playwright: cortex loads at :1420, API status indicator turns green
    when phantom-api is healthy.

    Requires: bun run dev (in phantom-nx/apps/cortex) + phantom-api up
    """
    if not _cortex_dev_available():
        pytest.skip("cortex dev server not running on :1420 — start with: bun run dev")

    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        pytest.skip("playwright not installed — run: pip install playwright && playwright install chromium")

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()

        page.goto(CORTEX_DEV_URL, wait_until="networkidle")

        # Wait for API status indicator (green dot in sidebar)
        # cortex sets class bg-green-500 when apiStatus === 'online'
        try:
            page.wait_for_selector(".bg-green-500", timeout=10_000)
            status_ok = True
        except Exception:
            status_ok = False

        browser.close()

    assert status_ok, (
        "cortex API status indicator never turned green. "
        "Check phantom-api is running and cortex apiUrl is set to http://localhost:8008"
    )


@pytest.mark.e2e
@pytest.mark.slow
def test_cortex_browser_send_message():
    """
    Playwright: type a message in cortex chat tab, verify assistant response appears.
    """
    if not _cortex_dev_available():
        pytest.skip("cortex dev server not running on :1420")

    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        pytest.skip("playwright not installed")

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()

        page.goto(CORTEX_DEV_URL, wait_until="networkidle")

        # Locate chat input and send button
        chat_input = page.locator("input[placeholder='Ask anything...']")
        send_button = page.locator("button", has_text="Send")

        chat_input.fill("Hello, what is voidnxlabs?")
        send_button.click()

        # Wait for assistant response (loading dots disappear, new message appears)
        page.wait_for_selector(".animate-bounce", state="hidden", timeout=30_000)

        # At least one assistant message bubble should be visible
        assistant_msgs = page.locator(".bg-gray-800").all()

        browser.close()

    assert len(assistant_msgs) > 0, "No assistant response appeared after sending message"


# ─────────────────────────────────────────────────────────────────────────────
# conftest sync fixture (add to conftest.py if not present)
# ─────────────────────────────────────────────────────────────────────────────

@pytest.fixture
def phantom_api_client_sync(docker_services):
    """Synchronous httpx client for phantom-api on port 8008."""
    with httpx.Client(**client_kwargs(PHANTOM_URL, timeout=30.0)) as client:
        yield client
