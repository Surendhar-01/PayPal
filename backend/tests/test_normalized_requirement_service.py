from datetime import datetime, timezone

from app.services import normalized_requirement_service

PREVIOUS_UPDATED_AT = datetime(2000, 1, 1, tzinfo=timezone.utc)


class _Result:
    def __init__(self, data):
        self.data = data


class _Query:
    def __init__(self, payload):
        self.payload = payload
        self.previous_updated_at = PREVIOUS_UPDATED_AT

    def upsert(self, payload, **_kwargs):
        self.payload = dict(payload)
        return self

    def update(self, payload):
        self.payload = dict(payload)
        return self

    def eq(self, *_args):
        return self

    def execute(self):
        return _Result([self.payload])


class _Client:
    def __init__(self):
        self.query = _Query({})

    def table(self, _name):
        return self.query


def test_extract_and_save_advances_normalized_snapshot_timestamp(monkeypatch):
    client = _Client()
    monkeypatch.setattr(normalized_requirement_service, "get_supabase_client", lambda: client)
    monkeypatch.setattr(
        normalized_requirement_service,
        "extract_requirements",
        lambda _demand: {"status": "Pending"},
    )

    saved = normalized_requirement_service.extract_and_save("demand-1", {})

    updated_at = datetime.fromisoformat(saved["updated_at"])
    assert updated_at > client.query.previous_updated_at
    assert updated_at.tzinfo == timezone.utc


def test_review_normalized_advances_normalized_snapshot_timestamp(monkeypatch):
    client = _Client()
    monkeypatch.setattr(normalized_requirement_service, "get_supabase_client", lambda: client)

    saved = normalized_requirement_service.review_normalized(
        "requirement-1",
        "customer-1",
        {"normalized_material": "steel"},
    )

    updated_at = datetime.fromisoformat(saved["updated_at"])
    assert updated_at > client.query.previous_updated_at
    assert updated_at.tzinfo == timezone.utc
    assert saved["normalized_material"] == "steel"