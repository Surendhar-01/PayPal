import httpx
import pytest

from app.core.config import Settings
from app.services.ai.health import check_ai_health


def _settings(**overrides) -> Settings:
    values = {
        "AI_PROVIDER": "groq",
        "GROQ_MODEL": "llama-3.1-8b-instant",
        "GROQ_API_KEY": "gsk_test-key",
        "ENVIRONMENT": "production",
    }
    values.update(overrides)
    return Settings(_env_file=None, **values)


@pytest.mark.anyio
async def test_ai_health_is_operational_when_model_is_present():
    def handle_request(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/openai/v1/models"
        return httpx.Response(200, json={"data": [{"id": "llama-3.1-8b-instant"}]})

    status = await check_ai_health(
        _settings(), transport=httpx.MockTransport(handle_request)
    )

    assert status.status == "operational"
    assert "llama-3.1-8b-instant" in status.message
    assert status.latency_ms is not None


@pytest.mark.anyio
async def test_ai_health_is_degraded_when_model_is_missing():
    def handle_request(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"data": [{"id": "another-model:7b"}]})

    status = await check_ai_health(
        _settings(), transport=httpx.MockTransport(handle_request)
    )

    assert status.status == "degraded"
    assert "llama-3.1-8b-instant" in status.message


@pytest.mark.anyio
async def test_ai_health_is_unavailable_on_http_error():
    def handle_request(_: httpx.Request) -> httpx.Response:
        return httpx.Response(500, json={"error": "internal detail"})

    status = await check_ai_health(
        _settings(), transport=httpx.MockTransport(handle_request)
    )

    assert status.status == "unavailable"
    assert "HTTP 500" in status.message
    assert "internal detail" not in status.message


@pytest.mark.anyio
async def test_ai_health_is_unavailable_on_connection_error():
    def handle_request(_: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("connection refused")

    status = await check_ai_health(
        _settings(GROQ_API_KEY="super-secret-token"),
        transport=httpx.MockTransport(handle_request),
    )

    assert status.status == "unavailable"
    assert "super-secret-token" not in (status.message or "")


@pytest.mark.anyio
async def test_ai_health_is_unavailable_on_timeout():
    def handle_request(_: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("timed out")

    status = await check_ai_health(
        _settings(GROQ_HEALTH_TIMEOUT_SECONDS=1.5),
        transport=httpx.MockTransport(handle_request),
    )

    assert status.status == "unavailable"
    assert "1.5s" in status.message


@pytest.mark.anyio
async def test_ai_health_flags_loopback_in_deployed_environment_without_request():
    """Groq uses a fixed remote API URL, so loopback never applies."""
    def handle_request(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"data": [{"id": "llama-3.1-8b-instant"}]})

    status = await check_ai_health(
        _settings(ENVIRONMENT="production"),
        transport=httpx.MockTransport(handle_request),
    )

    assert status.status == "operational"


@pytest.mark.anyio
async def test_ai_health_sends_bearer_token_when_configured():
    seen = {}

    def handle_request(request: httpx.Request) -> httpx.Response:
        seen["authorization"] = request.headers.get("authorization")
        return httpx.Response(200, json={"data": [{"id": "llama-3.1-8b-instant"}]})

    status = await check_ai_health(
        _settings(GROQ_API_KEY="endpoint-token"),
        transport=httpx.MockTransport(handle_request),
    )

    assert status.status == "operational"
    assert seen["authorization"] == "Bearer endpoint-token"


@pytest.mark.anyio
async def test_ai_health_reports_unsupported_provider_as_unconfigured():
    status = await check_ai_health(
        _settings(AI_PROVIDER="unknown-provider"),
        transport=httpx.MockTransport(
            lambda _: httpx.Response(200, json={"data": []})
        ),
    )

    assert status.status == "unconfigured"
    assert "unknown-provider" in status.message


@pytest.mark.anyio
async def test_ai_health_reports_missing_api_key_as_unconfigured():
    status = await check_ai_health(
        _settings(GROQ_API_KEY=""),
        transport=httpx.MockTransport(
            lambda _: httpx.Response(200, json={"data": []})
        ),
    )

    assert status.status == "unconfigured"
    assert "No Groq API key" in status.message


@pytest.mark.anyio
async def test_ai_health_reports_invalid_api_key():
    def handle_request(_: httpx.Request) -> httpx.Response:
        return httpx.Response(401, json={"error": "invalid api key"})

    status = await check_ai_health(
        _settings(),
        transport=httpx.MockTransport(handle_request),
    )

    assert status.status == "unavailable"
    assert "invalid" in status.message.lower() or "401" in status.message
