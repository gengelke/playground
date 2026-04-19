from __future__ import annotations

import sys
from pathlib import Path

import app.ingest as ingest_module
import requests
from app.chat import ChatService
from app.history import clear_history, list_history
from app.ingest import ingest_paths
from app.llm import call_anthropic, selected_provider_model
from app.models import ChatRequest, LLMResult
from app.embeddings import embed_text
from app.retrieval import concrete_ingest_profiles, search_qdrant, search_sqlite_chunks, tokenize


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
            },
            {
                "name": "echo_body",
                "usage": "echo body <value>",
                "match": {"patterns": ["^echo body\\s+.+$"]},
                "command": [sys.executable, "-c", "import sys; print(sys.argv[1])", "{tool_message}"],
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
        "history": {
            "enabled": True,
            "sqlite_path": "data/history.sqlite",
            "max_entries": 500,
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


def test_answer_is_recorded_in_history(tmp_path: Path) -> None:
    config = base_config(tmp_path)
    service = ChatService(config)
    response = service.answer(ChatRequest(message="How are you?"))
    items = list_history(config)
    assert response.metadata["history_id"] == items[0]["id"]
    assert items[0]["message"] == "How are you?"
    assert items[0]["answer"] == "I'm fine"
    assert clear_history(config) == 1


def test_pattern_rule(tmp_path: Path) -> None:
    service = ChatService(base_config(tmp_path))
    response = service.answer(ChatRequest(message="help"))
    assert response.answer == "help text"
    assert response.source == "rule_pattern"


def test_configured_tool_is_whitelisted(tmp_path: Path) -> None:
    service = ChatService(base_config(tmp_path))
    response = service.answer(ChatRequest(message="Simon says safe echo"))
    assert response.answer == "safe output"
    assert response.source == "tool"
    assert response.tool == "echo_safe"


def test_configured_tool_requires_simon_says_prefix(tmp_path: Path) -> None:
    service = ChatService(base_config(tmp_path))
    response = service.answer(ChatRequest(message="safe echo"))
    assert response.source != "tool"


def test_configured_tool_can_receive_message_body(tmp_path: Path) -> None:
    service = ChatService(base_config(tmp_path))
    response = service.answer(ChatRequest(message="Simon says echo body Erika Mustermann Developer"))
    assert response.answer == "echo body Erika Mustermann Developer"
    assert response.source == "tool"
    assert response.tool == "echo_body"


def test_configured_tool_requires_token_when_command_auth_is_enabled(tmp_path: Path, monkeypatch) -> None:
    config = base_config(tmp_path)
    config["auth"] = {"command_auth_required": True, "command_token_env": "TEST_CHATBOT_COMMAND_TOKEN"}
    monkeypatch.setenv("TEST_CHATBOT_COMMAND_TOKEN", "vip-secret")

    response = ChatService(config).answer(ChatRequest(message="Simon says safe echo"))

    assert response.source == "auth"
    assert "Authentication is required" in response.answer
    assert response.metadata["command_requested"] is True


def test_configured_tool_accepts_valid_command_token(tmp_path: Path, monkeypatch) -> None:
    config = base_config(tmp_path)
    config["auth"] = {"command_auth_required": True, "command_token_env": "TEST_CHATBOT_COMMAND_TOKEN"}
    monkeypatch.setenv("TEST_CHATBOT_COMMAND_TOKEN", "vip-secret")

    response = ChatService(config).answer(ChatRequest(message="Simon says safe echo", command_token="vip-secret"))

    assert response.answer == "safe output"
    assert response.source == "tool"
    assert response.tool == "echo_safe"


def test_show_commands_lists_simon_says_commands(tmp_path: Path) -> None:
    service = ChatService(base_config(tmp_path))
    response = service.answer(ChatRequest(message="show commands"))
    assert response.source == "rule_exact"
    assert "Available commands:" in response.answer
    assert "- Simon says safe echo" in response.answer
    assert "- Simon says echo body <value>" in response.answer
    assert response.metadata["commands"] == ["safe echo", "echo body <value>"]


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


def test_ingestion_accepts_selected_profiles(tmp_path: Path) -> None:
    config = base_config(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "note.txt").write_text("Jenkins job status can be read from its REST API.", encoding="utf-8")

    result = ingest_paths(config, ["docs"], reset=True, profiles=["sqlite", "qdrant_local_hash"])

    assert result["profiles"] == ["sqlite", "qdrant_local_hash"]
    assert result["ingested"][0]["profile_results"]["sqlite"]["stored"] is True
    assert result["ingested"][0]["profile_results"]["qdrant_local_hash"]["stored"] is False


def test_concrete_ingest_profiles_expands_hybrid(tmp_path: Path) -> None:
    config = base_config(tmp_path)

    profiles = concrete_ingest_profiles(config, ["hybrid"])

    assert [profile["name"] for profile in profiles] == ["qdrant_local_hash", "sqlite"]


def test_openai_embedding_uses_api_key(tmp_path: Path, monkeypatch) -> None:
    config = base_config(tmp_path)
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    captured = {}

    class FakeResponse:
        def raise_for_status(self):
            return None

        def json(self):
            return {"data": [{"embedding": [0.1, 0.2, 0.3]}]}

    def fake_post(url, headers=None, json=None, timeout=None):
        captured["url"] = url
        captured["headers"] = headers
        captured["json"] = json
        captured["timeout"] = timeout
        return FakeResponse()

    monkeypatch.setattr("app.embeddings.requests.post", fake_post)

    vector, metadata = embed_text(
        config,
        {
            "provider": "openai",
            "model": "text-embedding-3-small",
            "base_url": "https://api.openai.com/v1/embeddings",
            "api_key_env": "OPENAI_API_KEY",
        },
        "Jenkins playground note",
    )

    assert vector == [0.1, 0.2, 0.3]
    assert captured["headers"]["Authorization"] == "Bearer test-key"
    assert captured["json"]["model"] == "text-embedding-3-small"
    assert metadata["provider"] == "openai"


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
    assert response.metadata["retrieval"]["profile"] == "hybrid"


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


def test_qdrant_search_reranks_exact_command_chunk(tmp_path: Path, monkeypatch) -> None:
    config = base_config(tmp_path)
    config["qdrant"] = {
        "enabled": True,
        "min_query_chars": 4,
        "min_query_tokens": 2,
        "min_score": 0.2,
        "candidate_multiplier": 5,
        "min_candidates": 20,
        "lexical_rerank_weight": 2.0,
        "lexical_min_score": 0.45,
    }
    config["retrieval"] = {
        "profiles": [
            {
                "name": "qdrant_local_hash",
                "type": "qdrant",
                "collection": "test_chunks",
                "embedding": {"provider": "local_hash", "model": "local-hash-96", "vector_size": 96},
            }
        ]
    }

    class FakePoint:
        def __init__(self, score: float, text: str):
            self.score = score
            self.payload = {"text": text, "source_path": "docs/faq.md", "chunk_id": int(score * 1000)}

    class FakeClient:
        def search(self, collection_name, query_vector, limit):
            assert collection_name == "test_chunks"
            assert limit == 20
            return [
                FakePoint(0.90, "The DevOps Playground is a local playground."),
                FakePoint(0.80, "The playground includes Vault, Gitea, Jenkins, and Ollama."),
                FakePoint(0.10, "How do I start the DevOps Playground? Run make all MODE=docker."),
            ]

    monkeypatch.setattr("app.retrieval.ensure_qdrant_collection", lambda *args, **kwargs: True)
    monkeypatch.setattr("app.retrieval.get_qdrant_client", lambda _config: FakeClient())
    monkeypatch.setattr("app.retrieval.embed_with_profile", lambda *args, **kwargs: ([0.1] * 96, {}))

    chunks = search_qdrant(config, "how do i start the devops playground", limit=1, profile_name="qdrant_local_hash")

    assert chunks[0].text == "How do I start the DevOps Playground? Run make all MODE=docker."


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

    assert response.source == "llm_error"
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


def test_local_files_mode_ignores_stopwords_when_selecting_excerpt(tmp_path: Path) -> None:
    config = base_config(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "devops-playground.md").write_text(
        "# DevOps Playground Notes\n\n"
        "This chatbot is intended to run as an optional service in the DevOps playground.\n\n"
        "# The Author of DevOps Playground\n\n"
        "Gordon Engelke is the author and maintainer of the DevOps Playground\n",
        encoding="utf-8",
    )
    (docs / "playground-faq.md").write_text(
        "# DevOps Playground Detailed FAQ\n\n"
        "The DevOps Playground is an educational repository for experimenting with local DevOps tools.\n",
        encoding="utf-8",
    )
    config["local_files"] = [
        {
            "name": "docs",
            "enabled": True,
            "path": "docs",
            "max_files": 10,
            "max_chars": 1200,
            "match": {"patterns": ["playground"]},
        }
    ]

    service = ChatService(config)
    response = service.answer(ChatRequest(message="who is an author", use_rag=False, use_local_files=True))

    assert response.source == "local_file"
    assert "Gordon Engelke is the author and maintainer" in response.answer
    assert "educational repository" not in response.answer


def test_local_files_mode_ranks_across_multiple_sources(tmp_path: Path) -> None:
    config = base_config(tmp_path)
    sample_docs = tmp_path / "sample_docs"
    uploads = tmp_path / "uploads"
    sample_docs.mkdir()
    uploads.mkdir()
    (sample_docs / "playground-faq.md").write_text(
        "You can also work inside a service directory.",
        encoding="utf-8",
    )
    (uploads / "ai-notes.md").write_text(
        "Directory embeddings support semantic retrieval.",
        encoding="utf-8",
    )
    config["local_files"] = [
        {
            "name": "sample_docs",
            "enabled": True,
            "path": "sample_docs",
            "max_files": 10,
            "max_chars": 1200,
            "match": {"patterns": ["playground", "faq"]},
        },
        {
            "name": "prepared_uploads",
            "enabled": True,
            "path": "uploads",
            "max_files": 10,
            "max_chars": 1200,
            "match": {"patterns": ["ai", "uploaded", "document"]},
        },
    ]

    service = ChatService(config)
    response = service.answer(ChatRequest(message="directory embeddings retrieval", use_rag=False, use_local_files=True))

    assert response.source == "local_file"
    assert "Directory embeddings support semantic retrieval" in response.answer
    assert "You can also work inside a service directory" not in response.answer


def test_local_files_retrieval_profile_returns_file_answer_without_llm(tmp_path: Path, monkeypatch) -> None:
    config = base_config(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "faq.md").write_text(
        "## Who is the author?\n\nGordon Engelke is the author and maintainer of the DevOps Playground.",
        encoding="utf-8",
    )
    config["local_files"] = [
        {
            "name": "docs",
            "enabled": True,
            "path": "docs",
            "max_files": 10,
            "max_chars": 1200,
            "match": {"patterns": ["author"]},
        }
    ]

    def fake_llm(*args, **kwargs):
        raise AssertionError("local_files retrieval profile should not call the LLM")

    monkeypatch.setattr("app.chat.call_llm", fake_llm)

    service = ChatService(config)
    response = service.answer(ChatRequest(message="who is the author", retrieval_profile="local_files", use_rag=True))

    assert response.source == "local_file"
    assert "Gordon Engelke is the author" in response.answer
    assert response.metadata["retrieval"]["profile"] == "local_files"
    assert response.metadata["context"][0]["source"].startswith("local_files:local_files:")


def test_local_files_and_rag_are_mutually_exclusive(tmp_path: Path) -> None:
    service = ChatService(base_config(tmp_path))
    response = service.answer(ChatRequest(message="Jenkins", use_rag=True, use_local_files=True))

    assert response.source == "validation"
    assert response.answer == "Choose either RAG or local files, not both."


def test_llm_error_is_returned_instead_of_raw_rag_context(tmp_path: Path) -> None:
    config = base_config(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "note.txt").write_text("Jenkins job status can be read from its REST API.", encoding="utf-8")
    ingest_paths(config, ["docs"], reset=True)

    service = ChatService(config)
    response = service.answer(ChatRequest(message="Jenkins REST status", use_rag=True))

    assert response.source == "llm_error"
    assert response.answer == "Local LLM provider is disabled."
    assert response.metadata["llm"]["error"] == "provider_disabled"
    assert "Jenkins job status" in response.metadata["context"][0]["text"]


def test_anthropic_without_api_key_returns_llm_error_with_rag_context_metadata(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    config = base_config(tmp_path)
    config["providers"]["anthropic"] = {
        "default_model": "claude-test",
        "api_key_env": "ANTHROPIC_API_KEY",
    }
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "note.txt").write_text("Gordon Engelke is the author of the DevOps Playground.", encoding="utf-8")
    ingest_paths(config, ["docs"], reset=True)

    service = ChatService(config)
    response = service.answer(ChatRequest(message="Who is the author?", provider="anthropic", use_rag=True))

    assert response.source == "llm_error"
    assert response.provider == "anthropic"
    assert response.metadata["llm"]["error"] == "missing_api_key"
    assert "Anthropic is selected" in response.answer
    assert "Gordon Engelke" in response.metadata["context"][0]["text"]


def test_anthropic_http_error_includes_response_body(tmp_path: Path, monkeypatch) -> None:
    config = base_config(tmp_path)
    config["providers"]["anthropic"] = {
        "default_model": "claude-test",
        "api_key_env": "ANTHROPIC_API_KEY",
        "base_url": "https://api.anthropic.com/v1/messages",
    }
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")

    class FakeResponse:
        status_code = 400
        text = '{"error":{"type":"invalid_request_error","message":"bad request details"}}'

        def raise_for_status(self):
            raise requests.HTTPError("400 Client Error", response=self)

        def json(self):
            return {"error": {"type": "invalid_request_error", "message": "bad request details"}}

    monkeypatch.setattr("app.llm.requests.post", lambda *args, **kwargs: FakeResponse())

    result = call_anthropic(config, "hello", "claude-test")

    assert result.metadata["status_code"] == 400
    assert result.metadata["response_json"]["error"]["message"] == "bad request details"
    assert "bad request details" in result.metadata["response_text"]


def test_chat_uses_selected_sqlite_retrieval_profile(tmp_path: Path, monkeypatch) -> None:
    config = base_config(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "note.txt").write_text("Jenkins job status can be read from its REST API.", encoding="utf-8")
    ingest_paths(config, ["docs"], reset=True)

    def fake_llm(config, message, provider=None, model=None, context=None):
        return LLMResult("Jenkins job status can be read from its REST API.", "local", "test-model")

    monkeypatch.setattr("app.chat.call_llm", fake_llm)

    service = ChatService(config)
    response = service.answer(ChatRequest(message="Jenkins REST status", retrieval_profile="sqlite", use_rag=True))

    assert response.source == "llm"
    assert response.metadata["retrieval"]["profile"] == "sqlite"
    assert response.metadata["context"][0]["source"] == "sqlite:docs/note.txt"


def test_compare_runs_each_retrieval_profile(tmp_path: Path, monkeypatch) -> None:
    config = base_config(tmp_path)
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "note.txt").write_text("Jenkins job status can be read from its REST API.", encoding="utf-8")
    ingest_paths(config, ["docs"], reset=True)

    def fake_llm(config, message, provider=None, model=None, context=None):
        return LLMResult(context[0]["source"], "local", "test-model")

    monkeypatch.setattr("app.chat.call_llm", fake_llm)

    service = ChatService(config)
    result = service.compare(ChatRequest(message="Jenkins REST status"), ["sqlite", "qdrant_local_hash"])

    assert [item["retrieval_profile"] for item in result["results"]] == ["sqlite", "qdrant_local_hash"]
    assert result["results"][0]["source"] == "llm"
    assert result["results"][1]["source"] == "rag_empty"
