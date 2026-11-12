"""Safe descriptions of the configured AI provider target.

These helpers exist so logs and health checks can name the provider endpoint and
model without ever exposing credentials or query parameters that may be embedded
in a configured URL.
"""

from typing import Dict
from urllib.parse import urlsplit

from app.core.config import Settings

_LOOPBACK_HOSTS = {"localhost", "127.0.0.1", "::1", "0.0.0.0"}
_LOCAL_ENVIRONMENTS = {"development", "dev", "local", "test", "testing"}


def safe_groq_base_url(base_url: str) -> str:
    """Return ``scheme://host[:port]`` without userinfo, path, or query."""
    raw = (base_url or "").strip()
    if not raw:
        return "<unset>"
    try:
        parts = urlsplit(raw)
        host = parts.hostname
        port = parts.port
    except ValueError:
        return "<invalid>"
    if not parts.scheme or not host:
        return "<invalid>"
    return f"{parts.scheme}://{host}{f':{port}' if port else ''}"


def is_loopback_url(base_url: str) -> bool:
    """Return True when the configured URL targets this machine only."""
    try:
        host = urlsplit((base_url or "").strip()).hostname
    except ValueError:
        return False
    return (host or "").lower() in _LOOPBACK_HOSTS


def groq_request_headers(settings: Settings) -> Dict[str, str]:
    """Build request headers, including bearer authentication."""
    api_key = (settings.GROQ_API_KEY or "").strip()
    if not api_key:
        return {}
    return {"Authorization": f"Bearer {api_key}"}


def provider_context(settings: Settings) -> str:
    """A log-safe summary of the configured AI provider target."""
    provider = (settings.AI_PROVIDER or "").strip().lower() or "unset"
    model = (settings.GROQ_MODEL or "").strip() or "<unset>"
    return f"provider={provider}, model={model}"


def loopback_in_deployed_environment(settings: Settings) -> bool:
    """Groq uses a fixed remote API URL, so loopback never applies."""
    return False
