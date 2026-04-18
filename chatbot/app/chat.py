from __future__ import annotations

from typing import Any

from app.config import load_config
from app.llm import call_llm, selected_provider_model
from app.models import ChatRequest, ChatResponse, RetrievedChunk
from app.retrieval import hybrid_search
from app.sources import (
    format_rows,
    match_exact_rule,
    match_pattern_rule,
    normalize_text,
    query_configured_sqlite,
    query_rest_sources,
    run_configured_tool,
    search_local_files,
    search_web,
)


GENERATION_HINTS = (
    "summarize",
    "summary",
    "explain",
    "explanation",
    "synthesize",
    "compare",
    "why",
    "how",
    "zusammenfassen",
    "erkläre",
    "erklaere",
    "warum",
)


class ChatService:
    def __init__(self, config: dict[str, Any] | None = None):
        self.config = config or load_config()

    def answer(self, request: ChatRequest) -> ChatResponse:
        message = request.message.strip()
        if not message:
            return ChatResponse(answer="Please enter a question.", source="validation")

        normalized = normalize_text(message)
        provider, model = selected_provider_model(self.config, request.provider, request.model)
        use_rag = request.use_rag or request.rag_only
        if use_rag and request.use_local_files:
            return ChatResponse(
                answer="Choose either RAG or local files, not both.",
                source="validation",
                metadata={"use_rag": use_rag, "use_local_files": request.use_local_files},
            )

        exact_rule = match_exact_rule(self.config, message)
        if exact_rule:
            return ChatResponse(
                answer=exact_rule.get("answer", ""),
                source="rule_exact",
                metadata={"matched": exact_rule.get("question"), "normalized": normalized},
            )

        pattern_rule = match_pattern_rule(self.config, message)
        if pattern_rule:
            return ChatResponse(
                answer=pattern_rule.get("answer", ""),
                source="rule_pattern",
                metadata={"pattern": pattern_rule.get("pattern")},
            )

        if request.use_local_files:
            local_file_result = search_local_files(self.config, message)
            if local_file_result:
                return ChatResponse(
                    answer=format_file_answer(local_file_result),
                    source="local_file",
                    metadata=local_file_result,
                )
            return ChatResponse(
                answer="No relevant local file content found.",
                source="local_file_empty",
                metadata={"use_local_files": True},
            )

        tool_result = run_configured_tool(self.config, message)
        if tool_result:
            if tool_result.get("error"):
                return ChatResponse(
                    answer=f"Configured tool '{tool_result.get('name')}' failed: {tool_result.get('error')}",
                    source="tool",
                    tool=tool_result.get("name"),
                    metadata=tool_result,
                )
            return ChatResponse(
                answer=tool_result.get("output") or "(tool returned no output)",
                source="tool",
                tool=tool_result.get("name"),
                metadata=tool_result,
            )

        if not use_rag:
            sqlite_result = query_configured_sqlite(self.config, message)
            if sqlite_result:
                if sqlite_result.get("error"):
                    return ChatResponse(
                        answer=f"SQLite source '{sqlite_result.get('name')}' is unavailable: {sqlite_result.get('error')}",
                        source="sqlite_source",
                        metadata=sqlite_result,
                    )
                return ChatResponse(
                    answer=format_rows(sqlite_result.get("rows", [])),
                    source="sqlite_source",
                    metadata=sqlite_result,
                )

            rest_result = query_rest_sources(self.config, message)
            if rest_result:
                if rest_result.get("error") or int(rest_result.get("status_code", 500)) >= 400:
                    return ChatResponse(
                        answer=f"REST source '{rest_result.get('name')}' is unavailable or returned an error.",
                        source="rest_source",
                        metadata=rest_result,
                    )
                return ChatResponse(
                    answer=format_rest_answer(rest_result),
                    source="rest_source",
                    metadata=rest_result,
                )

        rag_chunks: list[RetrievedChunk] = []
        if use_rag:
            rag_chunks = hybrid_search(self.config, message)

        if use_rag and not rag_chunks:
            return ChatResponse(
                answer="No relevant RAG context found.",
                source="rag_empty",
                metadata={"context": [], "use_rag": use_rag},
            )

        web_result = None if use_rag else search_web(self.config, message, request.use_web_search)
        if web_result and web_result.get("answer") and not should_call_llm(message, request):
            return ChatResponse(answer=web_result["answer"], source="web_search", metadata=web_result)

        context = chunks_to_context(rag_chunks)
        if web_result and web_result.get("related"):
            context.append({"source": "web_search", "text": "\n".join(web_result["related"])})

        llm_result = call_llm(self.config, message, provider=provider, model=model, context=context)
        if rag_chunks and llm_result.metadata.get("error"):
            return ChatResponse(
                answer=format_chunks(rag_chunks),
                source="rag_context",
                provider=llm_result.provider,
                model=llm_result.model,
                metadata={"llm": llm_result.metadata, "chunks": chunks_metadata(rag_chunks)},
            )

        return ChatResponse(
            answer=llm_result.answer,
            source="llm" if not llm_result.metadata.get("error") else "none",
            provider=llm_result.provider,
            model=llm_result.model,
            metadata={"llm": llm_result.metadata, "context": context},
        )


def should_call_llm(message: str, request: ChatRequest) -> bool:
    if request.force_llm:
        return True
    normalized = normalize_text(message)
    return any(hint in normalized for hint in GENERATION_HINTS)


def format_file_answer(result: dict[str, Any]) -> str:
    lines = [f"Local file source: {result.get('name')}"]
    for match in result.get("matches", []):
        lines.append(f"\n{match.get('path')}:\n{match.get('text')}")
    return "\n".join(lines).strip()


def format_rest_answer(result: dict[str, Any]) -> str:
    return f"REST source: {result.get('name')}\nStatus: {result.get('status_code')}\n\n{result.get('body')}"


def format_chunks(chunks: list[RetrievedChunk]) -> str:
    lines = ["Relevant RAG context:"]
    for chunk in chunks:
        label = f"{chunk.source_path}"
        if chunk.chunk_index is not None:
            label += f" chunk {chunk.chunk_index}"
        lines.append(f"\n[{chunk.retriever} score={chunk.score:.3f}] {label}\n{chunk.text}")
    return "\n".join(lines)


def chunks_metadata(chunks: list[RetrievedChunk]) -> list[dict[str, Any]]:
    return [
        {
            "source_path": chunk.source_path,
            "chunk_id": chunk.chunk_id,
            "chunk_index": chunk.chunk_index,
            "score": chunk.score,
            "retriever": chunk.retriever,
        }
        for chunk in chunks
    ]


def chunks_to_context(chunks: list[RetrievedChunk]) -> list[dict[str, str]]:
    return [{"source": f"{chunk.retriever}:{chunk.source_path}", "text": chunk.text} for chunk in chunks]
