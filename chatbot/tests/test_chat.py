from __future__ import annotations

import sys
from pathlib import Path

import app.ingest as ingest_module
from app.chat import ChatService
from app.ingest import ingest_paths
from app.llm import selected_provider_model
from app.models import ChatRequest, LLMResult
from app.retrieval import search_qdrant, search_sqlite_chunks, tokenize


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


def test_sqlite_document_chunks_are_sent_to_llm_context(tmp_path: Path, monkeypatch) -> None:
    config = base_config(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "note.txt").write_text("Jenkins job status can be read from its REST API.", encoding="utf-8")

    result = ingest_paths(config, ["docs"], reset=True)
    assert result["ingested"][0]["chunks"] == 1

    captured = {}

    def fake_llm(config, message, provider=None, model=None, context=None):
        captured["context"] = context
        return LLMResult("Jenkins job status can be read from its REST API.", "local", "test-model")

    monkeypatch.setattr("app.chat.call_llm", fake_llm)

    service = ChatService(config)
    response = service.answer(ChatRequest(message="Jenkins REST status"))
    assert response.source == "llm"
    assert "Jenkins job status" in response.answer
    assert captured["context"][0]["source"] == "sqlite:docs/note.txt"


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


def test_pdf_ingestion_prepares_markdown_and_ingests_it(tmp_path: Path, monkeypatch) -> None:
    config = base_config(tmp_path)
    config["documents"]["prepared_path"] = "data/uploads/prepared"
    config["documents"]["pdf_section_chars"] = 1000
    config["documents"]["pdf_min_section_chars"] = 100
    pdf_path = tmp_path / "book.pdf"
    pdf_path.write_bytes(b"%PDF-test")

    def fake_extract_pdf_pages(path: Path):
        return [
            ingest_module.PdfPageText(1, "Book Title\n\nChapter 1 Introduction\n\nDevOps playground basics.\n\n1"),
            ingest_module.PdfPageText(2, "Book Title\n\nChapter 2 Commands\n\nUse make up-chatbot MODE=docker.\n\n2"),
        ]

    monkeypatch.setattr(ingest_module, "extract_pdf_pages", fake_extract_pdf_pages)

    result = ingest_paths(config, ["book.pdf"], reset=True)

    assert result["prepared"][0]["source"] == "book.pdf"
    assert result["prepared"][0]["pages"] == 2
    assert result["prepared"][0]["sections"] >= 1
    assert result["ingested"][0]["path"].startswith("data/uploads/prepared/book/")
    prepared_files = [tmp_path / path for path in result["prepared"][0]["prepared_files"]]
    assert all(path.exists() for path in prepared_files)
    prepared_text = "\n".join(path.read_text(encoding="utf-8") for path in prepared_files)
    assert "Source PDF: book.pdf" in prepared_text
    assert "Use make up-chatbot MODE=docker." in prepared_text
    assert "Book Title" not in prepared_text


def test_direct_question_gets_answer_from_llm_with_rag_context(tmp_path: Path, monkeypatch) -> None:
    config = base_config(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "note.md").write_text(
        "Gordon Engelke is the author and maintainer of the DevOps Playground\n"
        "So lorem ipsum is true",
        encoding="utf-8",
    )
    ingest_paths(config, ["docs"], reset=True)

    captured = {}

    def fake_llm(config, message, provider=None, model=None, context=None):
        captured["message"] = message
        captured["context"] = context
        return LLMResult("Gordon Engelke is the author and maintainer of the DevOps Playground.", "local", "test-model")

    monkeypatch.setattr("app.chat.call_llm", fake_llm)

    service = ChatService(config)
    response = service.answer(ChatRequest(message="Who is Gordon Engelke?", use_rag=True))

    assert response.source == "llm"
    assert response.answer == "Gordon Engelke is the author and maintainer of the DevOps Playground."
    assert captured["message"] == "Who is Gordon Engelke?"
    assert "Gordon Engelke is the author" in captured["context"][0]["text"]


def test_relation_question_is_handled_by_llm_with_rag_context(tmp_path: Path, monkeypatch) -> None:
    config = base_config(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "note.md").write_text(
        "Gordon Engelke is the author and maintainer of the DevOps Playground",
        encoding="utf-8",
    )
    ingest_paths(config, ["docs"], reset=True)

    captured = {}

    def fake_llm(config, message, provider=None, model=None, context=None):
        captured["context"] = context
        return LLMResult("I don't know from the RAG context.", "local", "test-model")

    monkeypatch.setattr("app.chat.call_llm", fake_llm)

    service = ChatService(config)
    response = service.answer(ChatRequest(message="Does Gordon Engelke know a popel?", use_rag=True))

    assert response.source == "llm"
    assert response.answer == "I don't know from the RAG context."
    assert "Gordon Engelke is the author" in captured["context"][0]["text"]


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


def test_tokenizer_splits_uploaded_file_names() -> None:
    assert tokenize("data/uploads/python_leitfaden.txt") == ["data", "uploads", "python", "leitfaden", "txt"]


def test_sqlite_search_uses_source_path_tokens(tmp_path: Path) -> None:
    config = base_config(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "python_leitfaden.txt").write_text("Dieses Dokument beschreibt Grundlagen.", encoding="utf-8")
    ingest_paths(config, ["docs"], reset=True)

    chunks = search_sqlite_chunks(config, "python leitfaden")

    assert chunks
    assert chunks[0].source_path == "docs/python_leitfaden.txt"


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


def test_rag_only_calls_llm_when_retrieval_matches(tmp_path: Path, monkeypatch) -> None:
    config = base_config(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "note.txt").write_text("Jenkins job status can be read from its REST API.", encoding="utf-8")
    ingest_paths(config, ["docs"], reset=True)

    def fake_llm(config, message, provider=None, model=None, context=None):
        return LLMResult("Jenkins job status can be read from its REST API.", "local", "test-model")

    monkeypatch.setattr("app.chat.call_llm", fake_llm)

    service = ChatService(config)
    response = service.answer(ChatRequest(message="Jenkins REST status", use_rag=True, rag_only=True, force_llm=True))

    assert response.source == "llm"
    assert "Jenkins job status" in response.answer


def test_rag_only_skips_configured_local_file_source(tmp_path: Path, monkeypatch) -> None:
    config = base_config(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "note.md").write_text("Jenkins is mentioned in the playground document.", encoding="utf-8")
    config["local_files"] = [
        {
            "name": "docs",
            "enabled": True,
            "path": "docs",
            "max_files": 10,
            "max_chars": 1200,
            "match": {"patterns": ["jenkins", "playground"]},
        }
    ]
    ingest_paths(config, ["docs"], reset=True)

    captured = {}

    def fake_llm(config, message, provider=None, model=None, context=None):
        captured["context"] = context
        return LLMResult("Jenkins is mentioned in the playground document.", "local", "test-model")

    monkeypatch.setattr("app.chat.call_llm", fake_llm)

    service = ChatService(config)
    response = service.answer(ChatRequest(message="Does Gordon have Jenkins in playground?", use_rag=True, rag_only=True))

    assert response.source == "llm"
    assert response.answer == "Jenkins is mentioned in the playground document."
    assert captured["context"][0]["source"] == "sqlite:docs/note.md"


def test_local_files_mode_uses_only_configured_local_files(tmp_path: Path) -> None:
    config = base_config(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "faq.md").write_text("The playground includes Jenkins and Ollama.", encoding="utf-8")
    config["local_files"] = [
        {
            "name": "docs",
            "enabled": True,
            "path": "docs",
            "max_files": 10,
            "max_chars": 1200,
            "match": {"patterns": ["jenkins", "playground"]},
        }
    ]

    service = ChatService(config)
    response = service.answer(ChatRequest(message="Which playground services mention Jenkins?", use_rag=False, use_local_files=True))

    assert response.source == "local_file"
    assert "The playground includes Jenkins and Ollama." in response.answer


def test_local_files_and_rag_are_mutually_exclusive(tmp_path: Path) -> None:
    service = ChatService(base_config(tmp_path))
    response = service.answer(ChatRequest(message="Jenkins", use_rag=True, use_local_files=True))

    assert response.source == "validation"
    assert response.answer == "Choose either RAG or local files, not both."


def test_rag_context_is_returned_if_llm_fails(tmp_path: Path) -> None:
    config = base_config(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "note.txt").write_text("Jenkins job status can be read from its REST API.", encoding="utf-8")
    ingest_paths(config, ["docs"], reset=True)

    service = ChatService(config)
    response = service.answer(ChatRequest(message="Jenkins REST status", use_rag=True))

    assert response.source == "rag_context"
    assert "Jenkins job status" in response.answer
