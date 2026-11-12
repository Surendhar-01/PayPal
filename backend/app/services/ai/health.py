"""Dependency probe for the configured AI provider."""

import time
from typing import Optional

import httpx

from app.core.config import Settings, get_settings
from app.schemas.health import ServiceStatus
from app.services.ai.diagnostics import (
    loopback_in_deployed_environment,
    provider_context,
    safe_groq_base_url,
)


async def check_ai_health(
    settings: Optional[Settings] = None,
    transport: Optional[httpx.AsyncBaseTransport] = None,
) -> ServiceStatus:
    """Probe Groq and report model availability without exposing credentials."""
    settings = settings or get_settings()
    provider = (settings.AI_PROVIDER or "").strip().lower()
    model = (settings.GROQ_MODEL or "").strip()
    api_key = (settings.GROQ_API_KEY or "").strip()

    if provider != "groq":
        return ServiceStatus(
            status="unconfigured",
            message=f"Unsupported AI provider configuration: '{provider or 'unset'}'.",
        )
    if not model:
        return ServiceStatus(
            status="unconfigured",
            message="No Groq model is configured.",
        )
    if not api_key:
        return ServiceStatus(
            status="unconfigured",
            message="No Groq API key is configured.",
        )
    if loopback_in_deployed_environment(settings):
        return ServiceStatus(
            status="unavailable",
            message=(
                "Groq is reachable only through a loopback address, which a deployed "
                "backend cannot reach. Configure a reachable endpoint."
            ),
        )

    timeout_seconds = settings.GROQ_HEALTH_TIMEOUT_SECONDS
    started = time.perf_counter()
    try:
        async with httpx.AsyncClient(
            timeout=httpx.Timeout(timeout_seconds, connect=timeout_seconds),
            transport=transport,
        ) as client:
            response = await client.get(
                "https://api.groq.com/openai/v1/models",
                headers={"Authorization": f"Bearer {api_key}"},
            )
    except httpx.TimeoutException:
        return ServiceStatus(
            status="unavailable",
            message=(
                f"Groq did not respond within {timeout_seconds:g}s."
            ),
            latency_ms=round((time.perf_counter() - started) * 1000, 2),
        )
    except httpx.RequestError as exc:
        return ServiceStatus(
            status="unavailable",
            message=(
                f"Groq is unreachable ({type(exc).__name__})."
            ),
            latency_ms=round((time.perf_counter() - started) * 1000, 2),
        )

    latency_ms = round((time.perf_counter() - started) * 1000, 2)
    if response.status_code == 401:
        return ServiceStatus(
            status="unavailable",
            message="Groq API key is invalid or missing.",
            latency_ms=latency_ms,
        )
    if response.status_code != 200:
        return ServiceStatus(
            status="unavailable",
            message=(
                f"Groq returned HTTP {response.status_code} for the model listing."
            ),
            latency_ms=latency_ms,
        )

    try:
        payload = response.json()
    except ValueError:
        return ServiceStatus(
            status="unavailable",
            message="Groq returned an invalid model listing.",
            latency_ms=latency_ms,
        )

    if not isinstance(payload, dict):
        return ServiceStatus(
            status="unavailable",
            message="Groq returned an invalid model listing.",
            latency_ms=latency_ms,
        )

    models = payload.get("data")
    if not isinstance(models, list):
        return ServiceStatus(
            status="unavailable",
            message="Groq returned an invalid model listing.",
            latency_ms=latency_ms,
        )
    model_ids = {m.get("id") for m in models if isinstance(m, dict)}
    if model not in model_ids:
        return ServiceStatus(
            status="degraded",
            message=(
                f"Groq is reachable, but model '{model}' is not available."
            ),
            latency_ms=latency_ms,
        )

    return ServiceStatus(
        status="operational",
        message=f"Groq is reachable; model '{model}' is available.",
        latency_ms=latency_ms,
    )
