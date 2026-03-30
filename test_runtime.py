from __future__ import annotations

import os
from pathlib import Path


SENTINEL_DIR = Path(__file__).resolve().parent
WORKSPACE_ROOT = Path(
    os.getenv("SENTINEL_WORKSPACE_ROOT", str(SENTINEL_DIR.parent))
).resolve()
DEFAULT_CA_CERT_FILE = WORKSPACE_ROOT / "secrets" / "tls" / "ca.crt"
DEFAULT_COMPOSE_FILE = SENTINEL_DIR / "docker-compose.yml"


def env_true(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def service_url(env_name: str, default: str) -> str:
    return os.getenv(env_name, default)


def http_verify(url: str):
    if not url.startswith("https://"):
        return True
    if env_true("SENTINEL_TLS_INSECURE", default=False):
        return False

    configured_ca = os.getenv("SENTINEL_CA_CERT")
    if configured_ca:
        return configured_ca
    if DEFAULT_CA_CERT_FILE.exists():
        return str(DEFAULT_CA_CERT_FILE)
    return True


def client_kwargs(url: str, timeout: float, **extra):
    kwargs = {
        "base_url": url,
        "timeout": timeout,
        "verify": http_verify(url),
    }
    kwargs.update(extra)
    return kwargs


def request_kwargs(url: str, timeout: float, **extra):
    kwargs = {
        "timeout": timeout,
        "verify": http_verify(url),
    }
    kwargs.update(extra)
    return kwargs


def compose_file() -> Path:
    override = os.getenv("SENTINEL_COMPOSE_FILE") or os.getenv(
        "SENTINEL_UMBRELLA_COMPOSE_FILE"
    )
    if override:
        return Path(override)
    return DEFAULT_COMPOSE_FILE
