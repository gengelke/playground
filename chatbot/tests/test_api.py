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
