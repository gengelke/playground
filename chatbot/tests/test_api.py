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
