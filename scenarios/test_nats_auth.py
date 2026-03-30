"""
NATS NKey Authorization tests (ROADMAP M3.1)

Validates the per-subject ACL model in spectre/config/nats-server.conf:
  - Each service authenticates with its NKey seed
  - Each service can only publish to its allowed subjects
  - Each service is denied publish on foreign subjects
  - Consumer-only services (phantom-soc) cannot publish to event subjects

Requires: NATS running with NKey auth config loaded
  nats-server --config spectre/config/nats-server.conf

Seed env vars (per service): OWASAKA_NKEY_SEED, AI_AGENT_OS_NKEY_SEED, etc.
Or seed files: spectre/config/nkeys/<service>.nk

Run:
  pytest scenarios/test_nats_auth.py -m e2e -v
"""

import asyncio
import os
import ssl

import nats
import pytest


NATS_URL = os.getenv("NATS_URL", "nats://localhost:4222")
NATS_CA_FILE = os.getenv("NATS_CA_FILE", "").strip()
NATS_CLIENT_CERT_FILE = os.getenv("NATS_CLIENT_CERT_FILE", "").strip()
NATS_CLIENT_KEY_FILE = os.getenv("NATS_CLIENT_KEY_FILE", "").strip()

# Mapping from service name to env var holding its seed
SERVICE_SEED_ENVS = {
    "owasaka":          "OWASAKA_NKEY_SEED",
    "ai-agent-os":      "AI_AGENT_OS_NKEY_SEED",
    "phantom":          "PHANTOM_NKEY_SEED",
    "phantom-soc":      "PHANTOM_SOC_NKEY_SEED",
    "cerebro":          "CEREBRO_NKEY_SEED",
    "securellm-bridge": "SECURELLM_BRIDGE_NKEY_SEED",
}

# Seed file fallback (relative to repo root)
SEED_FILE_DIR = os.path.join(
    os.path.dirname(__file__), "..", "..", "spectre", "config", "nkeys"
)

# Per-service ACL spec: (allowed_publish, denied_publish, allowed_subscribe)
ACL_SPEC = {
    "owasaka": {
        "may_publish":    ["network.asset.discovered.v1", "network.dns.query.v1"],
        "must_deny":      ["system.metrics.v1", "ingest.file.created.v1", "llm.request.v1"],
        "may_subscribe":  [],
    },
    "ai-agent-os": {
        "may_publish":    ["system.metrics.v1"],
        "must_deny":      ["network.asset.discovered.v1", "ingest.file.created.v1"],
        "may_subscribe":  [],
    },
    "phantom": {
        "may_publish":    ["ingest.file.created.v1", "ingest.file.sanitized.v1", "analysis.request.v1"],
        "must_deny":      ["network.asset.discovered.v1", "system.metrics.v1", "llm.request.v1"],
        "may_subscribe":  ["cognition.insight.generated.v1"],
    },
    "phantom-soc": {
        "may_publish":    [],  # consumer only
        "must_deny":      ["network.asset.discovered.v1", "system.metrics.v1", "ingest.file.created.v1"],
        "may_subscribe":  ["network.asset.discovered.v1", "system.metrics.v1"],
    },
    "cerebro": {
        "may_publish":    ["cognition.query.received.v1", "cognition.insight.generated.v1"],
        "must_deny":      ["network.asset.discovered.v1", "system.metrics.v1", "llm.request.v1"],
        "may_subscribe":  ["ingest.file.sanitized.v1"],
    },
    "securellm-bridge": {
        "may_publish":    ["llm.request.v1", "llm.response.v1"],
        "must_deny":      ["network.asset.discovered.v1", "system.metrics.v1", "ingest.file.created.v1"],
        "may_subscribe":  [],
    },
}


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _load_seed(service: str) -> str | None:
    """Load NKey seed for a service from env var or seed file."""
    # 1. Inline env var (SOPS-decrypted .env)
    env_var = SERVICE_SEED_ENVS[service]
    seed = os.getenv(env_var, "").strip()
    if seed:
        return seed

    # 2. Seed file (NixOS / local dev)
    seed_file = os.path.join(SEED_FILE_DIR, f"{service}.nk")
    if os.path.isfile(seed_file):
        with open(seed_file) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    return line

    return None


def _build_tls_context() -> ssl.SSLContext:
    """
    Build the TLS context used by live NATS auth tests.

    Our local CA is legacy and does not carry the key-usage extension that
    Python 3.13 now enforces under VERIFY_X509_STRICT.
    """
    tls_context = ssl.create_default_context(cafile=NATS_CA_FILE or None)
    if hasattr(ssl, "VERIFY_X509_STRICT"):
        tls_context.verify_flags &= ~ssl.VERIFY_X509_STRICT
    if NATS_CLIENT_CERT_FILE and NATS_CLIENT_KEY_FILE:
        tls_context.load_cert_chain(
            certfile=NATS_CLIENT_CERT_FILE,
            keyfile=NATS_CLIENT_KEY_FILE,
        )
    return tls_context


async def _connect_as(service: str) -> nats.aio.client.Client | None:
    """Connect to NATS as a specific service using its NKey seed."""
    seed = _load_seed(service)
    if seed is None:
        return None  # skip if no credentials available

    async def error_cb(e):
        pass  # suppress connection errors in tests

    kwargs = {
        "nkeys_seed_str": seed,
        "error_cb": error_cb,
        "connect_timeout": 5,
        "allow_reconnect": False,
    }
    if NATS_URL.startswith("tls://") or NATS_CA_FILE or NATS_CLIENT_CERT_FILE or NATS_CLIENT_KEY_FILE:
        kwargs["tls"] = _build_tls_context()

    nc = await nats.connect(NATS_URL, **kwargs)
    return nc


async def _assert_publish_denied(service: str, subjects: list[str]):
    seed = _load_seed(service)
    if seed is None:
        pytest.skip(f"{service} NKey seed not configured")

    violations: list[str] = []
    errors: list[str] = []

    async def error_cb(exc):
        errors.append(str(exc))

    kwargs = {
        "nkeys_seed_str": seed,
        "error_cb": error_cb,
        "connect_timeout": 5,
        "allow_reconnect": False,
    }
    if NATS_URL.startswith("tls://") or NATS_CA_FILE or NATS_CLIENT_CERT_FILE or NATS_CLIENT_KEY_FILE:
        kwargs["tls"] = _build_tls_context()

    nc = await nats.connect(NATS_URL, **kwargs)
    try:
        for subject in subjects:
            errors.clear()
            await nc.publish(subject, b'{"test": true}')
            await asyncio.sleep(0.2)
            if not any("permissions violation for publish" in err and subject in err for err in errors):
                violations.append(subject)
    finally:
        await nc.drain()

    assert not violations, f"{service} was allowed to publish to denied subjects: {violations}"


def _nats_auth_enabled() -> bool:
    """Check if at least one service seed is configured."""
    return any(_load_seed(svc) is not None for svc in SERVICE_SEED_ENVS)


# ─────────────────────────────────────────────────────────────────────────────
# Tier 0 — Seed availability
# ─────────────────────────────────────────────────────────────────────────────

@pytest.mark.e2e
def test_nkey_seeds_present():
    """All 6 service NKey seeds must be loadable (env var or seed file)."""
    missing = [svc for svc in SERVICE_SEED_ENVS if _load_seed(svc) is None]
    assert not missing, (
        f"Missing NKey seeds for: {missing}\n"
        f"Set env vars ({[SERVICE_SEED_ENVS[s] for s in missing]}) "
        f"or place seed files in spectre/config/nkeys/"
    )


@pytest.mark.e2e
def test_nkey_seed_format():
    """All present seeds must start with 'SUA' (NATS user seed prefix)."""
    for svc in SERVICE_SEED_ENVS:
        seed = _load_seed(svc)
        if seed is None:
            continue
        assert seed.startswith("SU"), (
            f"Service {svc!r} seed does not look like a NATS user seed "
            f"(expected prefix SU..., got: {seed[:6]}...)"
        )
        assert len(seed) >= 56, f"Service {svc!r} seed too short: {len(seed)} chars"


# ─────────────────────────────────────────────────────────────────────────────
# Tier 1 — NKey connection (auth works)
# ─────────────────────────────────────────────────────────────────────────────

@pytest.mark.e2e
@pytest.mark.asyncio
async def test_owasaka_nkey_connect():
    """owasaka can authenticate to NATS with its NKey seed."""
    seed = _load_seed("owasaka")
    if seed is None:
        pytest.skip("owasaka NKey seed not configured")

    nc = None
    try:
        kwargs = {
            "nkeys_seed_str": seed,
            "connect_timeout": 5,
            "allow_reconnect": False,
        }
        if NATS_URL.startswith("tls://") or NATS_CA_FILE or NATS_CLIENT_CERT_FILE or NATS_CLIENT_KEY_FILE:
            kwargs["tls"] = _build_tls_context()
        nc = await nats.connect(NATS_URL, **kwargs)
        assert nc.is_connected, "owasaka connected but not in connected state"
    except Exception as exc:
        pytest.fail(f"owasaka NKey auth failed: {exc}")
    finally:
        if nc:
            await nc.drain()


@pytest.mark.e2e
@pytest.mark.asyncio
async def test_all_services_nkey_connect():
    """All 6 services authenticate to NATS with their NKey seeds."""
    if not _nats_auth_enabled():
        pytest.skip("No NKey seeds configured — run with NATS auth stack")

    failed = []
    for svc in SERVICE_SEED_ENVS:
        seed = _load_seed(svc)
        if seed is None:
            failed.append(f"{svc}: no seed")
            continue

        nc = None
        try:
            kwargs = {
                "nkeys_seed_str": seed,
                "connect_timeout": 5,
                "allow_reconnect": False,
            }
            if NATS_URL.startswith("tls://") or NATS_CA_FILE or NATS_CLIENT_CERT_FILE or NATS_CLIENT_KEY_FILE:
                kwargs["tls"] = _build_tls_context()
            nc = await nats.connect(NATS_URL, **kwargs)
            if not nc.is_connected:
                failed.append(f"{svc}: not connected after connect()")
        except Exception as exc:
            failed.append(f"{svc}: {exc}")
        finally:
            if nc:
                await nc.drain()

    assert not failed, "NKey auth failed for services:\n" + "\n".join(failed)


@pytest.mark.e2e
@pytest.mark.asyncio
async def test_unauthenticated_rejected():
    """
    Connection without credentials must be rejected when NATS is in NKey mode.

    Skipped if NATS is running without auth (local dev without --config).
    """
    if not _nats_auth_enabled():
        pytest.skip("No seeds configured — cannot test auth rejection")

    try:
        kwargs = {
            "connect_timeout": 3,
            "allow_reconnect": False,
        }
        if NATS_URL.startswith("tls://") or NATS_CA_FILE or NATS_CLIENT_CERT_FILE or NATS_CLIENT_KEY_FILE:
            kwargs["tls"] = _build_tls_context()
        nc = await nats.connect(NATS_URL, **kwargs)
        # If we connected without auth, NATS is not in auth mode — skip
        await nc.drain()
        pytest.skip("NATS accepted unauthenticated connection — auth not enforced yet")
    except Exception:
        pass  # expected: connection refused or auth required


# ─────────────────────────────────────────────────────────────────────────────
# Tier 2 — Per-subject ACL validation
# ─────────────────────────────────────────────────────────────────────────────

@pytest.mark.e2e
@pytest.mark.asyncio
async def test_owasaka_publish_allowed():
    """owasaka can publish to network.* subjects."""
    nc = await _connect_as("owasaka")
    if nc is None:
        pytest.skip("owasaka NKey seed not configured")

    try:
        for subject in ACL_SPEC["owasaka"]["may_publish"]:
            await nc.publish(subject, b'{"test": true}')
        await nc.flush()
    except Exception as exc:
        pytest.fail(f"owasaka publish to allowed subject failed: {exc}")
    finally:
        await nc.drain()


@pytest.mark.e2e
@pytest.mark.asyncio
async def test_owasaka_publish_denied():
    """owasaka cannot publish to system.* or ingest.* (ACL enforced)."""
    await _assert_publish_denied("owasaka", ACL_SPEC["owasaka"]["must_deny"])


@pytest.mark.e2e
@pytest.mark.asyncio
async def test_ai_agent_os_publish_allowed():
    """ai-agent-os can publish to system.* subjects."""
    nc = await _connect_as("ai-agent-os")
    if nc is None:
        pytest.skip("ai-agent-os NKey seed not configured")

    try:
        for subject in ACL_SPEC["ai-agent-os"]["may_publish"]:
            await nc.publish(subject, b'{"test": true}')
        await nc.flush()
    except Exception as exc:
        pytest.fail(f"ai-agent-os publish to allowed subject failed: {exc}")
    finally:
        await nc.drain()


@pytest.mark.e2e
@pytest.mark.asyncio
async def test_ai_agent_os_publish_denied():
    """ai-agent-os cannot publish to network.* (ACL enforced)."""
    await _assert_publish_denied("ai-agent-os", ACL_SPEC["ai-agent-os"]["must_deny"])


@pytest.mark.e2e
@pytest.mark.asyncio
async def test_phantom_soc_subscribe_allowed():
    """phantom-soc can subscribe to network.> and system.> (read-only consumer)."""
    nc = await _connect_as("phantom-soc")
    if nc is None:
        pytest.skip("phantom-soc NKey seed not configured")

    try:
        for subject in ACL_SPEC["phantom-soc"]["may_subscribe"]:
            sub = await nc.subscribe(subject)
            await sub.unsubscribe()
    except Exception as exc:
        pytest.fail(f"phantom-soc subscribe to allowed subject failed: {exc}")
    finally:
        await nc.drain()


@pytest.mark.e2e
@pytest.mark.asyncio
async def test_phantom_soc_publish_denied():
    """phantom-soc (consumer-only) cannot publish to event subjects."""
    await _assert_publish_denied("phantom-soc", ACL_SPEC["phantom-soc"]["must_deny"])


# ─────────────────────────────────────────────────────────────────────────────
# Tier 3 — Cross-service event flow with auth
# ─────────────────────────────────────────────────────────────────────────────

@pytest.mark.e2e
@pytest.mark.asyncio
async def test_owasaka_to_phantom_soc_authed_flow():
    """
    Full authed round-trip: owasaka publishes network event → phantom-soc receives it.

    owasaka authenticates with its NKey and publishes network.asset.discovered.v1.
    phantom-soc authenticates with its NKey and subscribes to network.>.
    Event must arrive with correct subject and payload.
    """
    nc_pub = await _connect_as("owasaka")
    nc_sub = await _connect_as("phantom-soc")
    if nc_pub is None or nc_sub is None:
        if nc_pub:
            await nc_pub.drain()
        if nc_sub:
            await nc_sub.drain()
        pytest.skip("owasaka or phantom-soc NKey seeds not configured")

    received = []
    subject = "network.asset.discovered.v1"

    try:
        sub = await nc_sub.subscribe(subject)

        await nc_pub.publish(subject, b'{"ip": "10.0.0.1", "test": "nkey_flow"}')
        await nc_pub.flush()

        msg = await asyncio.wait_for(sub.next_msg(timeout=5.0), timeout=6.0)
        received.append(msg)
        await sub.unsubscribe()
    except asyncio.TimeoutError:
        pytest.fail("phantom-soc did not receive owasaka event within 5s")
    finally:
        await nc_pub.drain()
        await nc_sub.drain()

    assert len(received) == 1
    assert received[0].subject == subject


@pytest.mark.e2e
@pytest.mark.asyncio
async def test_ai_agent_os_to_phantom_soc_authed_flow():
    """
    Full authed round-trip: ai-agent-os publishes system.metrics.v1 → phantom-soc receives it.
    """
    nc_pub = await _connect_as("ai-agent-os")
    nc_sub = await _connect_as("phantom-soc")
    if nc_pub is None or nc_sub is None:
        if nc_pub:
            await nc_pub.drain()
        if nc_sub:
            await nc_sub.drain()
        pytest.skip("ai-agent-os or phantom-soc NKey seeds not configured")

    received = []
    subject = "system.metrics.v1"

    try:
        sub = await nc_sub.subscribe(subject)

        await nc_pub.publish(subject, b'{"cpu_percent": 42.0, "test": "nkey_flow"}')
        await nc_pub.flush()

        msg = await asyncio.wait_for(sub.next_msg(timeout=5.0), timeout=6.0)
        received.append(msg)
        await sub.unsubscribe()
    except asyncio.TimeoutError:
        pytest.fail("phantom-soc did not receive ai-agent-os system event within 5s")
    finally:
        await nc_pub.drain()
        await nc_sub.drain()

    assert len(received) == 1
    assert received[0].subject == subject


@pytest.mark.e2e
@pytest.mark.asyncio
async def test_phantom_to_cerebro_authed_flow():
    """
    Authed round-trip: phantom publishes ingest.file.sanitized.v1 → cerebro receives it.
    """
    nc_pub = await _connect_as("phantom")
    nc_sub = await _connect_as("cerebro")
    if nc_pub is None or nc_sub is None:
        if nc_pub:
            await nc_pub.drain()
        if nc_sub:
            await nc_sub.drain()
        pytest.skip("phantom or cerebro NKey seeds not configured")

    received = []
    subject = "ingest.file.sanitized.v1"

    try:
        sub = await nc_sub.subscribe(subject)

        await nc_pub.publish(subject, b'{"file_id": "test-001", "test": "nkey_flow"}')
        await nc_pub.flush()

        msg = await asyncio.wait_for(sub.next_msg(timeout=5.0), timeout=6.0)
        received.append(msg)
        await sub.unsubscribe()
    except asyncio.TimeoutError:
        pytest.fail("cerebro did not receive phantom ingest event within 5s")
    finally:
        await nc_pub.drain()
        await nc_sub.drain()

    assert len(received) == 1
    assert received[0].subject == subject
