from __future__ import annotations

import re
from typing import Any

from app.config import load_config
from app.llm import call_llm, selected_provider_model
from app.models import ChatRequest, ChatResponse, RetrievedChunk
from app.retrieval import search_qdrant, search_sqlite_chunks
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

        local_file_result = search_local_files(self.config, message)
        if local_file_result:
            return ChatResponse(
                answer=format_file_answer(local_file_result),
                source="local_file",
                metadata=local_file_result,
            )

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

        sqlite_chunks: list[RetrievedChunk] = []
        qdrant_chunks: list[RetrievedChunk] = []
        use_rag = request.use_rag or request.rag_only
        if use_rag:
            sqlite_chunks = search_sqlite_chunks(self.config, message)
            if sqlite_chunks and (request.rag_only or not should_call_llm(message, request)):
                answer = direct_answer_from_chunks(message, sqlite_chunks)
                return ChatResponse(
                    answer=answer or format_chunks(sqlite_chunks),
                    source="sqlite_chunks",
                    metadata={"chunks": chunks_metadata(sqlite_chunks), "answer_mode": "extractive" if answer else "chunks"},
                )

            qdrant_chunks = search_qdrant(self.config, message)
            if qdrant_chunks and (request.rag_only or not should_call_llm(message, request)):
                answer = direct_answer_from_chunks(message, qdrant_chunks)
                return ChatResponse(
                    answer=answer or format_chunks(qdrant_chunks),
                    source="qdrant",
                    metadata={"chunks": chunks_metadata(qdrant_chunks), "answer_mode": "extractive" if answer else "chunks"},
                )

        if request.rag_only:
            return ChatResponse(
                answer="No relevant local document chunks found.",
                source="rag_empty",
                metadata={"context": [], "use_rag": use_rag},
            )

        web_result = search_web(self.config, message, request.use_web_search)
        if web_result and web_result.get("answer") and not should_call_llm(message, request):
            return ChatResponse(answer=web_result["answer"], source="web_search", metadata=web_result)

        context = chunks_to_context(qdrant_chunks or sqlite_chunks)
        if web_result and web_result.get("related"):
            context.append({"source": "web_search", "text": "\n".join(web_result["related"])})

        llm_result = call_llm(self.config, message, provider=provider, model=model, context=context)
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
    lines = ["Relevant local document chunks:"]
    for chunk in chunks:
        label = f"{chunk.source_path}"
        if chunk.chunk_index is not None:
            label += f" chunk {chunk.chunk_index}"
        lines.append(f"\n[{chunk.retriever} score={chunk.score:.3f}] {label}\n{chunk.text}")
    return "\n".join(lines)


def direct_answer_from_chunks(message: str, chunks: list[RetrievedChunk]) -> str | None:
    yes_no_answer = yes_no_answer_from_chunks(message, chunks)
    if yes_no_answer:
        return yes_no_answer

    subject = direct_question_subject(message)
    if not subject:
        return None

    answers = []
    for chunk in chunks:
        answer = subject_statement(subject, chunk.text)
        if answer:
            answers.append(answer)
    if not answers:
        return None
    return sorted(answers, key=len, reverse=True)[0]


def yes_no_answer_from_chunks(message: str, chunks: list[RetrievedChunk]) -> str | None:
    for subject, predicate in yes_no_question_candidates(message):
        answers = []
        matching_answers = []
        for chunk in chunks:
            statement = subject_statement(subject, chunk.text)
            if not statement:
                continue
            if predicate_matches_statement(predicate, statement):
                matching_answers.append(statement)
            answers.append(statement)
        if matching_answers:
            return f"Yes. {sorted(matching_answers, key=len, reverse=True)[0]}"
        if answers:
            return f"I found this: {sorted(answers, key=len, reverse=True)[0]}"
    return None


def yes_no_question_candidates(message: str) -> list[tuple[str, str]]:
    match = re.match(r"^\s*(?:is|was|are|were|ist|war|sind|waren)\s+(.+?)\??\s*$", message, flags=re.IGNORECASE)
    if not match:
        return []

    words = normalize_text(match.group(1).strip(" ?!.")).split()
    candidates: list[tuple[str, str]] = []
    for split_at in range(len(words) - 1, 0, -1):
        subject = " ".join(words[:split_at])
        predicate = " ".join(strip_leading_articles(words[split_at:]))
        if predicate:
            candidates.append((subject, predicate))
    return candidates


def strip_leading_articles(words: list[str]) -> list[str]:
    while words and words[0] in {"a", "an", "the"}:
        words = words[1:]
    return words


def predicate_matches_statement(predicate: str, statement: str) -> bool:
    predicate_words = [word for word in text_words(predicate) if word not in {"a", "an", "the"}]
    statement_words = set(text_words(statement))
    return bool(predicate_words) and all(word in statement_words for word in predicate_words)


def text_words(text: str) -> list[str]:
    return re.findall(r"[a-z0-9_\-äöüß]+", text.lower())


def direct_question_subject(message: str) -> str | None:
    patterns = (
        r"^\s*who\s+(?:is|was|are|were)\s+(.+?)\??\s*$",
        r"^\s*what\s+(?:is|was|are|were)\s+(.+?)\??\s*$",
        r"^\s*wer\s+(?:ist|war|sind|waren)\s+(.+?)\??\s*$",
        r"^\s*was\s+(?:ist|war|sind|waren)\s+(.+?)\??\s*$",
    )
    for pattern in patterns:
        match = re.match(pattern, message, flags=re.IGNORECASE)
        if match:
            return normalize_text(match.group(1).strip(" ?!."))
    return None


def subject_statement(subject: str, text: str) -> str | None:
    candidates = split_statement_candidates(text)
    subject_words = [re.escape(word) for word in subject.split() if word]
    if not subject_words:
        return None

    exact_subject = r"\b" + r"\s+".join(subject_words) + r"\b"
    first_word_with_name_tail = rf"\b{subject_words[0]}\b(?:\s+[A-Z][A-Za-z0-9_\-']+){{0,4}}"
    verb = r"(?:is|was|are|were|ist|war|sind|waren)"

    for candidate in candidates:
        match = re.search(rf"{exact_subject}\s+{verb}\b", candidate, flags=re.IGNORECASE)
        if match:
            return clean_statement(candidate[match.start() :])

    for candidate in candidates:
        match = re.search(rf"{first_word_with_name_tail}\s+{verb}\b", candidate, flags=re.IGNORECASE)
        if match:
            return clean_statement(candidate[match.start() :])

    return None


def split_statement_candidates(text: str) -> list[str]:
    text = re.sub(r"\s*#+\s*", "\n", text)
    parts = re.split(r"\n+|(?<=[.!?])\s+|\s+So\s+", text)
    return [part.strip(" -*\t") for part in parts if part.strip(" -*\t")]


def clean_statement(text: str) -> str:
    text = re.sub(r"\s+", " ", text).strip()
    if text and text[-1] not in ".!?":
        text += "."
    return text


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
