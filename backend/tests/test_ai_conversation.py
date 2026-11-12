import asyncio
import json
import logging
from typing import Sequence

import httpx
import pytest
from fastapi.testclient import TestClient

from app.core.config import Settings
from app.main import app
from app.schemas.ai import (
    AIConversationRequest,
    AIProviderResponse,
    ConversationMessage,
    RequirementDraft,
)
from app.services.ai.ai_factory import create_ai_provider
from app.services.ai.base import (
    AIProvider,
    AIProviderConfigurationError,
    AIProviderInvalidResponse,
    AIProviderResourceError,
    AIProviderTimeout,
    AIProviderUnavailable,
)
from app.services.ai.conversation_service import ConversationService
from app.services.ai.conversation_service import (
    _extract_explicit_requirements,
    _merge_draft,
    _remove_battery_capacity_split_fragments,
)
from app.services.ai.groq_provider import GroqProvider
from app.api.v1.endpoints import ai as ai_endpoint


class FakeProvider(AIProvider):
    def __init__(self, response: AIProviderResponse) -> None:
        self.response = response
        self.calls = 0

    async def converse(
        self,
        message: str,
        history: Sequence[ConversationMessage],
        requirement_draft: RequirementDraft,
    ) -> AIProviderResponse:
        self.calls += 1
        return self.response

    async def translate_requirement(self, text: str, language: str) -> str:
        return text

    async def explain_product_matches(self, evidence: dict) -> str:
        return "explanation"


def _draft_response() -> AIProviderResponse:
    return AIProviderResponse(
        assistant_message="I can help with that.",
        requirement_draft=RequirementDraft(
            product_name="Water Tank",
            product_type="Tank",
            category="Industrial Storage",
            mandatory_requirements={"material": "SS 304", "capacity": "5000 litres"},
            optional_preferences={},
            commercial_constraints={"quantity": "10", "unit": "units"},
            delivery_constraints={},
        ),
    )


@pytest.mark.anyio
async def test_groq_provider_sends_configured_model_and_validates_json():
    expected = _draft_response().model_dump()
    calls = []

    async def handle_request(request: httpx.Request) -> httpx.Response:
        payload = json.loads(request.content)
        calls.append(payload)
        return httpx.Response(
            200,
            json={"choices": [{"message": {"content": json.dumps(expected)}}]},
        )

    settings = Settings(
        _env_file=None,
        AI_PROVIDER="groq",
        GROQ_API_KEY="gsk_test-key",
        GROQ_MODEL="llama-3.1-8b-instant",
    )
    provider = GroqProvider(settings, transport=httpx.MockTransport(handle_request))
    result = await provider.converse(
        "I need ten tanks.",
        [ConversationMessage(role="user", content="A water storage tank.")],
        RequirementDraft(),
    )

    assert result.requirement_draft.mandatory_requirements["material"] == "SS 304"
    assert calls[0]["model"] == "llama-3.1-8b-instant"
    assert calls[0]["stream"] is False
    assert calls[0]["response_format"] == {"type": "json_object"}
    assert calls[0]["messages"][-1] == {"role": "user", "content": "I need ten tanks."}
    assert calls[0]["messages"][1] == {
        "role": "user",
        "content": "A water storage tank.",
    }
    assert "capacity/dimensions separate from purchase quantity" in calls[0]["messages"][0]["content"]
    assert "Preserve negative requirements with their negative meaning" in calls[0]["messages"][0]["content"]
    assert "Preserve complete price meaning and per-unit versus total-order context" in (
        calls[0]["messages"][0]["content"]
    )
    assert "variety_quantities" in calls[0]["messages"][0]["content"]


@pytest.mark.anyio
async def test_groq_invalid_json_raises_controlled_provider_error(caplog):
    calls = 0

    async def handle_request(_: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        return httpx.Response(200, json={"choices": [{"message": {"content": "not json"}}]})

    provider = GroqProvider(
        Settings(_env_file=None, AI_PROVIDER="groq", GROQ_API_KEY="gsk_test-key", GROQ_MODEL="llama-3.1-8b-instant"),
        transport=httpx.MockTransport(handle_request),
    )

    with pytest.raises(AIProviderInvalidResponse):
        await provider.converse("Need a tank", [], RequirementDraft())
    assert calls == 2
    assert "provider=groq" in caplog.text
    assert "failure_category=invalid_response" in caplog.text
    assert "elapsed_ms=" in caplog.text
    assert "Need a tank" not in caplog.text


@pytest.mark.anyio
async def test_groq_timeout_raises_provider_timeout():
    async def handle_request(_: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("timed out")

    provider = GroqProvider(
        Settings(_env_file=None, AI_PROVIDER="groq", GROQ_API_KEY="gsk_test-key", GROQ_MODEL="llama-3.1-8b-instant"),
        transport=httpx.MockTransport(handle_request),
    )

    with pytest.raises(AIProviderTimeout):
        await provider.converse("Need a tank", [], RequirementDraft())


@pytest.mark.anyio
async def test_groq_connection_error_raises_provider_unavailable():
    async def handle_request(_: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("connection refused")

    provider = GroqProvider(
        Settings(_env_file=None, AI_PROVIDER="groq", GROQ_API_KEY="gsk_test-key", GROQ_MODEL="llama-3.1-8b-instant"),
        transport=httpx.MockTransport(handle_request),
    )

    with pytest.raises(AIProviderUnavailable):
        await provider.converse("Need a tank", [], RequirementDraft())


@pytest.mark.anyio
async def test_groq_401_invalid_api_key():
    async def handle_request(_: httpx.Request) -> httpx.Response:
        return httpx.Response(401, json={"error": "Invalid API key"})

    provider = GroqProvider(
        Settings(_env_file=None, AI_PROVIDER="groq", GROQ_API_KEY="bad-key", GROQ_MODEL="llama-3.1-8b-instant"),
        transport=httpx.MockTransport(handle_request),
    )

    with pytest.raises(AIProviderUnavailable):
        await provider.converse("Need a tank", [], RequirementDraft())


@pytest.mark.anyio
async def test_groq_429_rate_limited():
    async def handle_request(_: httpx.Request) -> httpx.Response:
        return httpx.Response(429, json={"error": "Rate limit exceeded"})

    provider = GroqProvider(
        Settings(_env_file=None, AI_PROVIDER="groq", GROQ_API_KEY="gsk_test-key", GROQ_MODEL="llama-3.1-8b-instant"),
        transport=httpx.MockTransport(handle_request),
    )

    with pytest.raises(AIProviderUnavailable):
        await provider.converse("Need a tank", [], RequirementDraft())


@pytest.mark.anyio
async def test_groq_404_model_unavailable():
    """A 404 from Groq means the model is unavailable."""
    async def handle_request(_: httpx.Request) -> httpx.Response:
        return httpx.Response(404, json={"error": "Model not found"})

    provider = GroqProvider(
        Settings(_env_file=None, AI_PROVIDER="groq", GROQ_API_KEY="gsk_test-key", GROQ_MODEL="llama-3.1-8b-instant"),
        transport=httpx.MockTransport(handle_request),
    )

    with pytest.raises(AIProviderUnavailable):
        await provider.converse("Need a tank", [], RequirementDraft())


@pytest.mark.anyio
async def test_groq_invalid_model_configuration():
    with pytest.raises(AIProviderConfigurationError):
        GroqProvider(
            Settings(_env_file=None, AI_PROVIDER="groq", GROQ_API_KEY="gsk_test-key", GROQ_MODEL="invalid-model")
        )


@pytest.mark.anyio
async def test_groq_missing_api_key():
    with pytest.raises(AIProviderConfigurationError):
        GroqProvider(
            Settings(_env_file=None, AI_PROVIDER="groq", GROQ_API_KEY="", GROQ_MODEL="llama-3.1-8b-instant")
        )


# ---- Conversation endpoint tests using FakeProvider ----

@pytest.mark.anyio
async def test_conversation_endpoint_returns_200_with_fake_provider():
    client = TestClient(app)
    payload = {
        "message": "I need ten water tanks.",
        "conversation_history": [],
    }

    original = ai_endpoint.create_ai_provider

    def fake_create(*args, **kwargs):
        return FakeProvider(_draft_response())

    ai_endpoint.create_ai_provider = fake_create
    try:
        resp = client.post("/api/v1/ai/conversation", json=payload)
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "collecting_information"
        assert data["requirement_draft"]["product_name"] == "water tanks"
        assert "price" in data["assistant_message"].lower() or "budget" in data["assistant_message"].lower()
    finally:
        ai_endpoint.create_ai_provider = original


@pytest.mark.anyio
async def test_conversation_endpoint_rate_limits():
    client = TestClient(app)
    payload = {"message": "Need ten water tanks."}

    call_count = 0

    class CountingProvider(AIProvider):
        async def converse(self, message, history, requirement_draft):
            nonlocal call_count
            call_count += 1
            return _draft_response()

        async def translate_requirement(self, text, language):
            return text

        async def explain_product_matches(self, evidence):
            return "explanation"

    original = ai_endpoint.create_ai_provider
    ai_endpoint.create_ai_provider = lambda *a, **k: CountingProvider()
    try:
        # First request should succeed
        resp1 = client.post("/api/v1/ai/conversation", json=payload)
        assert resp1.status_code == 200
        # Send enough requests to exceed the rate limit (10 per window)
        rate_limited = False
        for _ in range(11):
            resp = client.post("/api/v1/ai/conversation", json=payload)
            if resp.status_code == 429:
                rate_limited = True
                break
        assert rate_limited, "Expected at least one rate-limited response"
    finally:
        ai_endpoint.create_ai_provider = original


@pytest.mark.anyio
async def test_conversation_endpoint_returns_503_when_provider_unavailable():
    client = TestClient(app)
    payload = {"message": "I need ten water tanks."}

    class UnavailableProvider(AIProvider):
        async def converse(self, message, history, requirement_draft):
            raise AIProviderUnavailable("The AI provider is unavailable.")

        async def translate_requirement(self, text, language):
            return text

        async def explain_product_matches(self, evidence):
            return "explanation"

    original = ai_endpoint.create_ai_provider
    ai_endpoint.create_ai_provider = lambda *a, **k: UnavailableProvider()
    try:
        resp = client.post("/api/v1/ai/conversation", json=payload)
        assert resp.status_code == 503
    finally:
        ai_endpoint.create_ai_provider = original


@pytest.mark.anyio
async def test_conversation_endpoint_returns_504_on_timeout():
    client = TestClient(app)
    payload = {"message": "I need ten water tanks."}

    class TimeoutProvider(AIProvider):
        async def converse(self, message, history, requirement_draft):
            raise AIProviderTimeout("The AI provider timed out.")

        async def translate_requirement(self, text, language):
            return text

        async def explain_product_matches(self, evidence):
            return "explanation"

    original = ai_endpoint.create_ai_provider
    ai_endpoint.create_ai_provider = lambda *a, **k: TimeoutProvider()
    try:
        resp = client.post("/api/v1/ai/conversation", json=payload)
        assert resp.status_code == 504
    finally:
        ai_endpoint.create_ai_provider = original


@pytest.mark.anyio
async def test_conversation_endpoint_returns_502_on_invalid_response():
    client = TestClient(app)
    payload = {"message": "I need ten water tanks."}

    class InvalidProvider(AIProvider):
        async def converse(self, message, history, requirement_draft):
            raise AIProviderInvalidResponse("Invalid response", public_message="Bad response")

        async def translate_requirement(self, text, language):
            return text

        async def explain_product_matches(self, evidence):
            return "explanation"

    original = ai_endpoint.create_ai_provider
    ai_endpoint.create_ai_provider = lambda *a, **k: InvalidProvider()
    try:
        resp = client.post("/api/v1/ai/conversation", json=payload)
        assert resp.status_code == 502
        data = resp.json()
        assert data["error"] == "Bad response"
    finally:
        ai_endpoint.create_ai_provider = original


@pytest.mark.anyio
async def test_translate_requirement_endpoint_returns_200():
    client = TestClient(app)
    payload = {"text": "नमस्कार", "language": "hi-IN"}

    class TranslationProvider(AIProvider):
        async def converse(self, message, history, requirement_draft):
            return _draft_response()

        async def translate_requirement(self, text, language):
            return "Hello"

        async def explain_product_matches(self, evidence):
            return "explanation"

    original = ai_endpoint.create_ai_provider
    ai_endpoint.create_ai_provider = lambda *a, **k: TranslationProvider()
    try:
        resp = client.post("/api/v1/ai/translate-requirement", json=payload)
        assert resp.status_code == 200
        assert resp.json()["translated_text"] == "Hello"
    finally:
        ai_endpoint.create_ai_provider = original


@pytest.mark.anyio
async def test_translate_requirement_endpoint_returns_503_when_unavailable():
    client = TestClient(app)
    payload = {"text": "น้ำถัง", "language": "hi-IN"}

    class UnavailableTranslationProvider(AIProvider):
        async def converse(self, message, history, requirement_draft):
            return _draft_response()

        async def translate_requirement(self, text, language):
            raise AIProviderUnavailable("Translation unavailable")

        async def explain_product_matches(self, evidence):
            return "explanation"

    original = ai_endpoint.create_ai_provider
    ai_endpoint.create_ai_provider = lambda *a, **k: UnavailableTranslationProvider()
    try:
        resp = client.post("/api/v1/ai/translate-requirement", json=payload)
        assert resp.status_code == 503
    finally:
        ai_endpoint.create_ai_provider = original


# ---- ConversationService tests ----

@pytest.mark.anyio
async def test_conversation_service_applies_backend_completeness_rules():
    provider = FakeProvider(_draft_response())
    service = ConversationService(provider)

    request = AIConversationRequest(
        message="I need a water tank.",
        conversation_history=[],
        requirement_draft=None,
    )

    response = await service.respond(request)
    assert response.status == "collecting_information"
    assert response.requirement_draft.product_name == "Water Tank"


@pytest.mark.anyio
async def test_conversation_service_preserves_history():
    provider = FakeProvider(_draft_response())
    service = ConversationService(provider)

    request = AIConversationRequest(
        message="Make it 5000 litres.",
        conversation_history=[
            ConversationMessage(role="user", content="I need a water tank."),
            ConversationMessage(role="assistant", content="I can help with that."),
        ],
        requirement_draft=RequirementDraft(product_name="Water Tank"),
    )

    response = await service.respond(request)
    assert response.status == "collecting_information"


# ---- Explicit requirement extraction tests ----

@pytest.mark.anyio
async def test_extract_explicit_requirements_product_name():
    from app.services.ai.conversation_service import (
        _extract_explicit_requirements,
    )

    messages = [
        ConversationMessage(role="user", content="I need a Dell XPS 13 laptop."),
    ]
    draft = _extract_explicit_requirements(messages)
    assert draft.product_name == "Dell XPS 13"
    assert draft.mandatory_requirements.get("brand") == "Dell"
    assert draft.mandatory_requirements.get("model") == "XPS 13"


@pytest.mark.anyio
async def test_extract_explicit_requirements_quantity():
    from app.services.ai.conversation_service import (
        _extract_explicit_requirements,
    )

    messages = [
        ConversationMessage(role="user", content="I need 5 units."),
    ]
    draft = _extract_explicit_requirements(messages)
    assert draft.commercial_constraints.get("quantity") == "5"


@pytest.mark.anyio
async def test_merge_draft():
    from app.services.ai.conversation_service import _merge_draft

    base = RequirementDraft(
        product_name="Tank",
        mandatory_requirements={"material": "SS 304"},
        optional_preferences={},
        commercial_constraints={"quantity": "10"},
        delivery_constraints={},
    )
    overlay = RequirementDraft(
        product_name=None,
        mandatory_requirements={"capacity": "5000 litres"},
        optional_preferences={"color": "blue"},
        commercial_constraints={"unit": "units"},
        delivery_constraints={},
    )
    merged = _merge_draft(base, overlay)
    assert merged.mandatory_requirements["material"] == "SS 304"
    assert merged.mandatory_requirements["capacity"] == "5000 litres"
    assert merged.optional_preferences["color"] == "blue"
    assert merged.commercial_constraints["quantity"] == "10"
    assert merged.commercial_constraints["unit"] == "units"


# ---- create_ai_provider tests ----

@pytest.mark.anyio
async def test_create_ai_provider_returns_groq_provider():
    settings = Settings(
        _env_file=None,
        AI_PROVIDER="groq",
        GROQ_API_KEY="gsk_test-key",
        GROQ_MODEL="llama-3.1-8b-instant",
    )
    provider = create_ai_provider(settings=settings)
    assert isinstance(provider, GroqProvider)


@pytest.mark.anyio
async def test_create_ai_provider_unsupported_provider():
    settings = Settings(
        _env_file=None,
        AI_PROVIDER="ollama",
        GROQ_API_KEY="gsk_test-key",
        GROQ_MODEL="llama-3.1-8b-instant",
    )
    with pytest.raises(AIProviderConfigurationError):
        create_ai_provider(settings=settings)
