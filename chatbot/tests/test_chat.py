from __future__ import annotations

import sys
from pathlib import Path

from app.chat import ChatService
from app.ingest import ingest_paths
from app.llm import selected_provider_model
from app.models import ChatRequest
from app.retrieval import search_qdrant


def base_config(tmp_path: Path) -> dict:
    return {
        "_project_root": str(tmp_path),
        "providers": {
            "default_provider": "local",
            "default_model": "test-model",
            "local": {"enabled": False},
        },
        "rules": {
            "exact": [{"question": "How are you?", "answer": "I'm fine"}],
            "patterns": [{"pattern": "^help$", "answer": "help text"}],
        },
        "tools": [
            {
                "name": "echo_safe",
                "match": {"exact": ["safe echo"]},
                "command": [sys.executable, "-c", "print('safe output')"],
                "timeout_seconds": 3,
            }
        ],
        "local_files": [],
        "sqlite_sources": [],
        "rest_sources": [],
        "documents": {
            "sqlite_path": "data/documents.sqlite",
            "top_k": 3,
            "chunk_size": 200,
            "chunk_overlap": 20,
            "min_query_chars": 4,
            "min_query_tokens": 2,
            "min_score": 0.25,
        },
        "qdrant": {"enabled": False},
        "web_search": {"enabled": False},
    }


def test_exact_rule_does_not_need_llm(tmp_path: Path) -> None:
    service = ChatService(base_config(tmp_path))
    response = service.answer(ChatRequest(message="How are you?"))
    assert response.answer == "I'm fine"
    assert response.source == "rule_exact"
    assert response.provider is None


def test_pattern_rule(tmp_path: Path) -> None:
    service = ChatService(base_config(tmp_path))
    response = service.answer(ChatRequest(message="help"))
    assert response.answer == "help text"
    assert response.source == "rule_pattern"


def test_configured_tool_is_whitelisted(tmp_path: Path) -> None:
    service = ChatService(base_config(tmp_path))
    response = service.answer(ChatRequest(message="safe echo"))
    assert response.answer == "safe output"
    assert response.source == "tool"
    assert response.tool == "echo_safe"


def test_sqlite_document_chunks_are_used_before_llm(tmp_path: Path) -> None:
    config = base_config(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "note.txt").write_text("Jenkins job status can be read from its REST API.", encoding="utf-8")

    result = ingest_paths(config, ["docs"], reset=True)
    assert result["ingested"][0]["chunks"] == 1

    service = ChatService(config)
    response = service.answer(ChatRequest(message="Jenkins REST status"))
    assert response.source == "sqlite_chunks"
    assert "Jenkins job status" in response.answer


def test_ingestion_skips_editor_files(tmp_path: Path) -> None:
    config = base_config(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "note.md").write_text("Gordon Engelke maintains the playground.", encoding="utf-8")
    (docs / ".note.md.swp").write_bytes(b"\x00temporary editor state")
    (docs / ".note.md.un~").write_bytes(b"\x00vim undo state")

    result = ingest_paths(config, ["docs"], reset=True)

    assert len(result["ingested"]) == 1
    assert result["ingested"][0]["path"] == "docs/note.md"
    skipped_paths = {Path(item["path"]).name for item in result["skipped"]}
    assert skipped_paths == {".note.md.swp", ".note.md.un~"}


def test_direct_question_gets_extracted_answer_from_chunks(tmp_path: Path) -> None:
    config = base_config(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "note.md").write_text(
        "Gordon Engelke is the author and maintainer of the DevOps Playground\n"
        "So lorem ipsum is true",
        encoding="utf-8",
    )
    ingest_paths(config, ["docs"], reset=True)

    service = ChatService(config)
    response = service.answer(ChatRequest(message="Who is Gordon Engelke?", use_rag=True))

    assert response.source == "sqlite_chunks"
    assert response.answer == "Gordon Engelke is the author and maintainer of the DevOps Playground."
    assert response.metadata["answer_mode"] == "extractive"

    short_response = service.answer(ChatRequest(message="Who is Gordon?", use_rag=True))

    assert short_response.answer == "Gordon Engelke is the author and maintainer of the DevOps Playground."

    yes_no_response = service.answer(ChatRequest(message="Is Gordon Engelke an author?", use_rag=True))

    assert yes_no_response.answer == "Yes. Gordon Engelke is the author and maintainer of the DevOps Playground."


def test_yes_no_question_prefers_complete_chunk_answer(tmp_path: Path) -> None:
    config = base_config(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "note.md").write_text(
        "# DevOps Playground Notes\n\n"
        "This chatbot is intended to run as an optional service in the DevOps playground. "
        "It can run by itself with SQLite storage and optional Qdrant semantic retrieval. "
        "The playground commonly includes Jenkins, Gitea, Nexus, Vault, Nginx, GitLab, and "
        "small API services. The chatbot should connect to those services through configuration, "
        "not through hardcoded service names.\n\n"
        "# The Author of DevOps Playground\n\n"
        "Gordon Engelke is the author and maintainer of the DevOps Playground\n",
        encoding="utf-8",
    )
    ingest_paths(config, ["docs"], reset=True)

    service = ChatService(config)
    response = service.answer(ChatRequest(message="Is Gordon Engelke an author?", use_rag=True))

    assert response.answer == "Yes. Gordon Engelke is the author and maintainer of the DevOps Playground."


def test_provider_specific_default_model_wins_for_provider_override(tmp_path: Path) -> None:
    config = base_config(tmp_path)
    config["providers"]["openai"] = {"default_model": "gpt-4.1-mini"}

    provider, model = selected_provider_model(config, provider="openai", model=None)

    assert provider == "openai"
    assert model == "gpt-4.1-mini"


def test_qdrant_search_ignores_too_short_queries(tmp_path: Path) -> None:
    config = base_config(tmp_path)
    config["qdrant"] = {
        "enabled": True,
        "min_query_chars": 4,
        "min_query_tokens": 2,
    }

    assert search_qdrant(config, "x") == []


def test_force_llm_without_rag_does_not_add_sqlite_context(tmp_path: Path) -> None:
    config = base_config(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "note.txt").write_text("Jenkins job status can be read from its REST API.", encoding="utf-8")
    ingest_paths(config, ["docs"], reset=True)

    service = ChatService(config)
    response = service.answer(ChatRequest(message="Explain Jenkins REST status", use_rag=False, force_llm=True))

    assert response.source == "none"
    assert response.metadata["context"] == []


def test_rag_only_returns_empty_instead_of_llm_for_no_match(tmp_path: Path) -> None:
    service = ChatService(base_config(tmp_path))
    response = service.answer(ChatRequest(message="popel", provider="openai", use_rag=True, rag_only=True))

    assert response.source == "rag_empty"
    assert response.provider is None
    assert response.metadata["context"] == []


def test_rag_only_returns_chunks_when_retrieval_matches(tmp_path: Path) -> None:
    config = base_config(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "note.txt").write_text("Jenkins job status can be read from its REST API.", encoding="utf-8")
    ingest_paths(config, ["docs"], reset=True)

    service = ChatService(config)
    response = service.answer(ChatRequest(message="Jenkins REST status", use_rag=True, rag_only=True, force_llm=True))

    assert response.source == "sqlite_chunks"
    assert "Jenkins job status" in response.answer
