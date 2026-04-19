from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass
class ChatRequest:
    message: str
    provider: str | None = None
    model: str | None = None
    retrieval_profile: str | None = None
    use_rag: bool = True
    rag_only: bool = False
    use_local_files: bool = False
    use_web_search: bool | None = None
    force_llm: bool = False


@dataclass
class ChatResponse:
    answer: str
    source: str
    provider: str | None = None
    model: str | None = None
    tool: str | None = None
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass
class RetrievedChunk:
    text: str
    source_path: str
    score: float
    chunk_id: int | None = None
    chunk_index: int | None = None
    retriever: str = "sqlite"


@dataclass
class LLMResult:
    answer: str
    provider: str
    model: str
    metadata: dict[str, Any] = field(default_factory=dict)
