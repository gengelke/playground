from __future__ import annotations

import time
from typing import Any

from app.auth import command_auth_status
from app.config import load_config
from app.history import record_chat
from app.llm import call_llm, selected_provider_model
from app.models import ChatRequest, ChatResponse, RetrievedChunk
from app.retrieval import default_retrieval_profile, get_retrieval_profile, search_retrieval_profile
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
    static_question_answer,
    tool_message_body,
)


GENERATION_HINTS = frozenset({
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
})


class ChatService:
    def __init__(self, config: dict[str, Any] | None = None):
        self.config = config or load_config()

    def answer(self, request: ChatRequest) -> ChatResponse:
        started = time.perf_counter()
        message = request.message.strip()
        if not message:
            return ChatResponse(answer="Please enter a question.", source="validation")

        provider, model = selected_provider_model(self.config, request.provider, request.model)
        use_rag = request.use_rag
        retrieval_profile = request.retrieval_profile or default_retrieval_profile(self.config)
        if use_rag and request.use_local_files:
            return self.finalize_response(request, ChatResponse(
                answer="Choose either RAG or local files, not both.",
                source="validation",
                metadata={"use_rag": use_rag, "use_local_files": request.use_local_files},
            ))

        static_answer = static_question_answer(self.config, message)
        if static_answer:
            return self.finalize_response(request, ChatResponse(
                answer=static_answer.get("answer", ""),
                source="rule_exact",
                metadata={"matched": static_answer.get("question"), "commands": static_answer.get("commands", [])},
            ))

        exact_rule = match_exact_rule(self.config, message)
        if exact_rule:
            return self.finalize_response(request, ChatResponse(
                answer=exact_rule.get("answer", ""),
                source="rule_exact",
                metadata={"matched": exact_rule.get("question"), "normalized": normalize_text(message)},
            ))

        pattern_rule = match_pattern_rule(self.config, message)
        if pattern_rule:
            return self.finalize_response(request, ChatResponse(
                answer=pattern_rule.get("answer", ""),
                source="rule_pattern",
                metadata={"pattern": pattern_rule.get("pattern")},
            ))

        tool_message = tool_message_body(message)
        if tool_message is not None:
            auth_status = command_auth_status(self.config, request.command_token)
            if not auth_status["authorized"]:
                return self.finalize_response(request, ChatResponse(
                    answer="Authentication is required to execute Simon says commands.",
                    source="auth",
                    metadata={
                        "command_requested": True,
                        "reason": auth_status.get("reason"),
                        "token_env": auth_status.get("token_env"),
                    },
                ))

            tool_result = run_configured_tool(self.config, message)
            if tool_result:
                if tool_result.get("error"):
                    return self.finalize_response(request, ChatResponse(
                        answer=f"Configured tool '{tool_result.get('name')}' failed: {tool_result.get('error')}",
                        source="tool",
                        tool=tool_result.get("name"),
                        metadata=tool_result,
                    ))
                return self.finalize_response(request, ChatResponse(
                    answer=tool_result.get("output") or "(tool returned no output)",
                    source="tool",
                    tool=tool_result.get("name"),
                    metadata=tool_result,
                ))

            return self.finalize_response(request, ChatResponse(
                answer="No configured Simon says command matched this request.",
                source="tool_empty",
                metadata={"command_requested": True, "tool_message": tool_message},
            ))

        if request.use_local_files:
            local_file_result = search_local_files(self.config, message, require_match=False)
            if local_file_result:
                return self.finalize_response(request, ChatResponse(
                    answer=format_file_answer(local_file_result),
                    source="local_file",
                    metadata=local_file_result,
                ))
            return self.finalize_response(request, ChatResponse(
                answer="No relevant local file content found.",
                source="local_file_empty",
                metadata={"use_local_files": True},
            ))

        if not use_rag:
            sqlite_result = query_configured_sqlite(self.config, message)
            if sqlite_result:
                if sqlite_result.get("error"):
                    return self.finalize_response(request, ChatResponse(
                        answer=f"SQLite source '{sqlite_result.get('name')}' is unavailable: {sqlite_result.get('error')}",
                        source="sqlite_source",
                        metadata=sqlite_result,
                    ))
                return self.finalize_response(request, ChatResponse(
                    answer=format_rows(sqlite_result.get("rows", [])),
                    source="sqlite_source",
                    metadata=sqlite_result,
                ))

            rest_result = query_rest_sources(self.config, message)
            if rest_result:
                if rest_result.get("error") or int(rest_result.get("status_code", 500)) >= 400:
                    return self.finalize_response(request, ChatResponse(
                        answer=f"REST source '{rest_result.get('name')}' is unavailable or returned an error.",
                        source="rest_source",
                        metadata=rest_result,
                    ))
                return self.finalize_response(request, ChatResponse(
                    answer=format_rest_answer(rest_result),
                    source="rest_source",
                    metadata=rest_result,
                ))

        rag_chunks: list[RetrievedChunk] = []
        retrieval_metadata: dict[str, Any] = {}
        if use_rag:
            retrieval_started = time.perf_counter()
            try:
                profile = get_retrieval_profile(self.config, retrieval_profile)
                retrieval_metadata = retrieval_profile_metadata(profile)
                rag_chunks = search_retrieval_profile(self.config, message, retrieval_profile)
            except Exception as exc:
                return self.finalize_response(request, ChatResponse(
                    answer=f"Retrieval profile '{retrieval_profile}' is unavailable: {exc}",
                    source="retrieval_error",
                    metadata={"retrieval_profile": retrieval_profile, "error": str(exc)},
                ))
            retrieval_metadata["latency_ms"] = elapsed_ms(retrieval_started)

        if use_rag and not rag_chunks:
            return self.finalize_response(request, ChatResponse(
                answer="No relevant RAG context found.",
                source="rag_empty",
                metadata={"context": [], "use_rag": use_rag, "retrieval": retrieval_metadata},
            ))

        web_result = None if use_rag else search_web(self.config, message, request.use_web_search)
        if web_result and web_result.get("answer") and not should_call_llm(message):
            return self.finalize_response(request, ChatResponse(answer=web_result["answer"], source="web_search", metadata=web_result))

        context = chunks_to_context(rag_chunks)
        if web_result and web_result.get("related"):
            context.append({"source": "web_search", "text": "\n".join(web_result["related"])})

        llm_started = time.perf_counter()
        llm_result = call_llm(self.config, message, provider=provider, model=model, context=context)
        llm_latency_ms = elapsed_ms(llm_started)
        if llm_result.metadata.get("error"):
            return self.finalize_response(request, ChatResponse(
                answer=llm_result.answer,
                source="llm_error",
                provider=llm_result.provider,
                model=llm_result.model,
                metadata={
                    "llm": {**llm_result.metadata, "latency_ms": llm_latency_ms},
                    "context": context,
                    "chunks": chunks_metadata(rag_chunks) if rag_chunks else [],
                    "retrieval": retrieval_metadata if use_rag else None,
                    "latency_ms": elapsed_ms(started),
                },
            ))

        return self.finalize_response(request, ChatResponse(
            answer=llm_result.answer,
            source="llm",
            provider=llm_result.provider,
            model=llm_result.model,
            metadata={
                "llm": {**llm_result.metadata, "latency_ms": llm_latency_ms},
                "context": context,
                "retrieval": retrieval_metadata if use_rag else None,
                "latency_ms": elapsed_ms(started),
            },
        ))

    def compare(self, request: ChatRequest, retrieval_profiles: list[str]) -> dict[str, Any]:
        results = []
        for profile in retrieval_profiles:
            response = self.answer(
                ChatRequest(
                    message=request.message,
                    provider=request.provider,
                    model=request.model,
                    retrieval_profile=profile,
                    command_token=request.command_token,
                    use_rag=True,
                    use_local_files=False,
                    use_web_search=False,
                )
            )
            results.append(
                {
                    "retrieval_profile": profile,
                    "answer": response.answer,
                    "source": response.source,
                    "provider": response.provider,
                    "model": response.model,
                    "tool": response.tool,
                    "metadata": response.metadata,
                }
            )
        return {"message": request.message, "results": results}

    def finalize_response(self, request: ChatRequest, response: ChatResponse) -> ChatResponse:
        history_id = record_chat(self.config, request, response)
        if history_id is not None:
            response.metadata = {**response.metadata, "history_id": history_id}
        return response


def should_call_llm(message: str) -> bool:
    normalized = normalize_text(message)
    return any(hint in normalized for hint in GENERATION_HINTS)


def format_file_answer(result: dict[str, Any]) -> str:
    source_names = result.get("source_names") or [result.get("name")]
    if len(source_names) == 1:
        lines = [f"Local file source: {source_names[0]}"]
    else:
        lines = [f"Local file sources: {', '.join(source_names)}"]
    for match in result.get("matches", []):
        source_name = match.get("source_name")
        prefix = f"\n[{source_name}]\n" if len(source_names) > 1 and source_name else "\n"
        lines.append(f"{prefix}{match.get('path')}:\n{match.get('text')}")
    return "\n".join(lines).strip()


def format_rest_answer(result: dict[str, Any]) -> str:
    return f"REST source: {result.get('name')}\nStatus: {result.get('status_code')}\n\n{result.get('body')}"



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


def retrieval_profile_metadata(profile: dict[str, Any]) -> dict[str, Any]:
    metadata = {
        "profile": profile.get("name"),
        "type": profile.get("type"),
    }
    if profile.get("collection"):
        metadata["collection"] = profile.get("collection")
    if profile.get("embedding"):
        metadata["embedding"] = profile.get("embedding")
    return metadata


def elapsed_ms(started: float) -> int:
    return int((time.perf_counter() - started) * 1000)
