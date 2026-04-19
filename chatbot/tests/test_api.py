from __future__ import annotations

from fastapi.testclient import TestClient

from app.main import app


def test_health_endpoint() -> None:
    client = TestClient(app)
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_chat_endpoint_exact_rule() -> None:
    client = TestClient(app)
    response = client.post("/api/chat", json={"message": "How are you?"})
    assert response.status_code == 200
    data = response.json()
    assert data["answer"] == "I'm fine"
    assert data["source"] == "rule_exact"


def test_chat_endpoint_denies_command_without_bearer_token(monkeypatch) -> None:
    monkeypatch.setenv("CHATBOT_COMMAND_TOKEN", "vip-secret")
    client = TestClient(app)
    response = client.post("/api/chat", json={"message": "Simon says get time"})

    assert response.status_code == 200
    data = response.json()
    assert data["source"] == "auth"
    assert "Authentication is required" in data["answer"]


def test_chat_endpoint_accepts_command_with_bearer_token(monkeypatch) -> None:
    monkeypatch.setenv("CHATBOT_COMMAND_TOKEN", "vip-secret")
    client = TestClient(app)
    response = client.post(
        "/api/chat",
        headers={"Authorization": "Bearer vip-secret"},
        json={"message": "Simon says get time"},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["source"] == "tool"
    assert data["tool"] == "local_time"


def test_history_endpoint_records_chat() -> None:
    client = TestClient(app)
    client.delete("/api/history")
    response = client.post("/api/chat", json={"message": "How are you?"})
    assert response.status_code == 200

    history = client.get("/api/history?limit=5")
    assert history.status_code == 200
    data = history.json()
    assert data["items"][0]["message"] == "How are you?"
    assert data["items"][0]["answer"] == "I'm fine"


def test_retrieval_profiles_endpoint() -> None:
    client = TestClient(app)
    response = client.get("/api/retrieval-profiles")

    assert response.status_code == 200
    data = response.json()
    names = {profile["name"] for profile in data["profiles"]}
    assert "sqlite" in names
    assert "qdrant_local_hash" in names
    assert "qdrant_anthropic_openai" in names


def test_chat_compare_endpoint() -> None:
    client = TestClient(app)
    response = client.post(
        "/api/chat/compare",
        json={"message": "How are you?", "retrieval_profiles": ["sqlite", "qdrant_local_hash"]},
    )

    assert response.status_code == 200
    data = response.json()
    assert [item["retrieval_profile"] for item in data["results"]] == ["sqlite", "qdrant_local_hash"]


def test_upload_ingest_endpoint() -> None:
    client = TestClient(app)
    response = client.post(
        "/api/ingest/files",
        data={"reset": "true"},
        files={"files": ("browser-note.md", b"Browser uploaded FAQ content.", "text/markdown")},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["uploaded"] == ["data/uploads/browser-note.md"]
    assert data["ingested"][0]["path"] == "data/uploads/browser-note.md"
