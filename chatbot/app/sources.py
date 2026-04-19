from __future__ import annotations

import json
import re
import sqlite3
import subprocess
from pathlib import Path
from typing import Any

import requests

from app.config import resolve_path
from app.ingest import read_document
from app.retrieval import tokenize

TOOL_PREFIX = "simon says"


def normalize_text(text: str) -> str:
    return " ".join(text.strip().lower().split())


def first_match(value: str, exact_values: list[str] | None = None, patterns: list[str] | None = None) -> bool:
    normalized = normalize_text(value)
    for exact in exact_values or []:
        if normalized == normalize_text(exact):
            return True
    for pattern in patterns or []:
        if re.search(pattern, value, flags=re.IGNORECASE):
            return True
    return False


def match_exact_rule(config: dict[str, Any], message: str) -> dict[str, Any] | None:
    normalized = normalize_text(message)
    for rule in config.get("rules", {}).get("exact", []):
        if normalize_text(rule.get("question", "")) == normalized:
            return rule
    return None


def match_pattern_rule(config: dict[str, Any], message: str) -> dict[str, Any] | None:
    for rule in config.get("rules", {}).get("patterns", []):
        if re.search(rule.get("pattern", ""), message, flags=re.IGNORECASE):
            return rule
    return None


def static_question_answer(config: dict[str, Any], message: str) -> dict[str, Any] | None:
    if normalize_text(message) != "show commands":
        return None

    commands = configured_tool_commands(config)
    if not commands:
        return {
            "question": "show commands",
            "answer": "No Simon says commands are configured.",
            "commands": [],
        }

    return {
        "question": "show commands",
        "answer": "Available commands:\n" + "\n".join(f"- Simon says {command}" for command in commands),
        "commands": commands,
    }


def run_configured_tool(config: dict[str, Any], message: str) -> dict[str, Any] | None:
    tool_message = tool_message_body(message)
    if not tool_message:
        return None

    for tool in config.get("tools", []):
        match = tool.get("match", {})
        if not first_match(tool_message, match.get("exact"), match.get("patterns")):
            continue

        command = tool.get("command")
        if not isinstance(command, list) or not all(isinstance(part, str) for part in command):
            return {"name": tool.get("name"), "error": "tool command must be a list of strings"}

        try:
            completed = subprocess.run(
                command,
                cwd=config.get("_project_root"),
                text=True,
                capture_output=True,
                timeout=float(tool.get("timeout_seconds", 5)),
                check=False,
            )
        except Exception as exc:
            return {"name": tool.get("name"), "error": str(exc)}

        output = (completed.stdout or completed.stderr or "").strip()
        return {
            "name": tool.get("name"),
            "returncode": completed.returncode,
            "output": output[:4000],
        }
    return None


def tool_message_body(message: str) -> str | None:
    normalized = normalize_text(message)
    if normalized == TOOL_PREFIX:
        return ""
    prefix = f"{TOOL_PREFIX} "
    if not normalized.startswith(prefix):
        return None
    return normalized[len(prefix):].strip()


def configured_tool_commands(config: dict[str, Any]) -> list[str]:
    commands: list[str] = []
    seen: set[str] = set()
    for tool in config.get("tools", []):
        for exact in tool.get("match", {}).get("exact", []) or []:
            normalized = normalize_text(str(exact))
            if not normalized or normalized in seen:
                continue
            seen.add(normalized)
            commands.append(normalized)
    return commands


def search_local_files(config: dict[str, Any], message: str, require_match: bool = True) -> dict[str, Any] | None:
    candidates = []
    matched_source_names: list[str] = []
    global_match_limit = 1

    for source in config.get("local_files", []):
        if source.get("enabled") is False:
            continue
        if require_match and not first_match(message, source.get("match", {}).get("exact"), source.get("match", {}).get("patterns")):
            continue

        path = resolve_path(config, source.get("path", ""))
        files = [path] if path.is_file() else []
        if path.is_dir():
            files = [item for item in path.rglob("*") if item.is_file()]

        excerpts = []
        for file_path in files[: int(source.get("max_files", 10))]:
            try:
                text = read_document(file_path)
            except Exception:
                continue
            excerpt, score = best_excerpt_with_score(text, message, int(source.get("max_chars", 1200)))
            if excerpt:
                excerpts.append(
                    {
                        "path": str(file_path),
                        "text": excerpt,
                        "score": score,
                        "source_name": source.get("name"),
                    }
                )
        if excerpts:
            matched_source_names.append(str(source.get("name")))
            excerpts.sort(key=lambda item: item["score"], reverse=True)
            source_best_score = excerpts[0]["score"]
            source_minimum_score = max(1.0, source_best_score * 0.5)
            source_match_limit = int(source.get("max_matches", source.get("max_files", 10)))
            global_match_limit = max(global_match_limit, source_match_limit)
            candidates.extend([item for item in excerpts if item["score"] >= source_minimum_score][:source_match_limit])

    if not candidates:
        return None

    candidates.sort(key=lambda item: item["score"], reverse=True)
    best_score = candidates[0]["score"]
    minimum_score = max(1.0, best_score * 0.5)
    matches = [item for item in candidates if item["score"] >= minimum_score][:global_match_limit]
    unique_source_names = list(dict.fromkeys(matched_source_names))
    return {
        "name": unique_source_names[0] if len(unique_source_names) == 1 else "multiple",
        "source_names": unique_source_names,
        "matches": matches,
    }


def query_configured_sqlite(config: dict[str, Any], message: str) -> dict[str, Any] | None:
    for source in config.get("sqlite_sources", []):
        if source.get("enabled") is False:
            continue
        if not first_match(message, source.get("match", {}).get("exact"), source.get("match", {}).get("patterns")):
            continue

        path = resolve_path(config, source.get("path", ""))
        if not path.exists():
            return {"name": source.get("name"), "error": f"sqlite database not found: {path}"}

        try:
            with sqlite3.connect(path) as conn:
                conn.row_factory = sqlite3.Row
                rows = conn.execute(
                    source.get("query", "SELECT 1 AS value"),
                    {"query": message, "like_query": f"%{message}%"},
                ).fetchmany(int(source.get("limit", 5)))
        except Exception as exc:
            return {"name": source.get("name"), "error": str(exc)}

        return {"name": source.get("name"), "rows": [dict(row) for row in rows]}
    return None


def query_rest_sources(config: dict[str, Any], message: str) -> dict[str, Any] | None:
    for source in config.get("rest_sources", []):
        if source.get("enabled") is False:
            continue
        if not first_match(message, source.get("match", {}).get("exact"), source.get("match", {}).get("patterns")):
            continue

        method = source.get("method", "GET").upper()
        url = source.get("url")
        timeout = float(source.get("timeout_seconds", 3))
        try:
            if method == "POST":
                response = requests.post(url, json={"query": message}, timeout=timeout)
            else:
                response = requests.get(url, params={"q": message} if source.get("send_query_param", True) else None, timeout=timeout)
            body = response.text[:4000]
            return {
                "name": source.get("name"),
                "url": url,
                "status_code": response.status_code,
                "body": try_json(body),
            }
        except Exception as exc:
            return {"name": source.get("name"), "url": url, "error": str(exc)}
    return None


def search_web(config: dict[str, Any], message: str, enabled_override: bool | None = None) -> dict[str, Any] | None:
    web = config.get("web_search", {})
    enabled = web.get("enabled", False) if enabled_override is None else enabled_override
    if not enabled:
        return None

    provider = web.get("provider", "duckduckgo")
    if provider != "duckduckgo":
        return {"provider": provider, "error": "only duckduckgo is implemented in this simple version"}

    try:
        response = requests.get(
            web.get("url", "https://api.duckduckgo.com/"),
            params={"q": message, "format": "json", "no_redirect": "1", "no_html": "1"},
            timeout=float(web.get("timeout_seconds", 4)),
        )
        response.raise_for_status()
        data = response.json()
    except Exception as exc:
        return {"provider": provider, "error": str(exc)}

    answer = data.get("AbstractText") or data.get("Answer")
    related = []
    for topic in data.get("RelatedTopics", []):
        if isinstance(topic, dict) and topic.get("Text"):
            related.append(topic["Text"])
        if len(related) >= 3:
            break
    return {"provider": provider, "answer": answer, "related": related}


def best_excerpt(text: str, query: str, max_chars: int = 1200) -> str:
    excerpt, _score = best_excerpt_with_score(text, query, max_chars=max_chars)
    return excerpt


def best_excerpt_with_score(text: str, query: str, max_chars: int = 1200) -> tuple[str, float]:
    if not text.strip():
        return "", 0.0
    query_tokens = query_search_tokens(query)
    if not query_tokens:
        return text[:max_chars].strip(), 1.0

    paragraphs = [part.strip() for part in re.split(r"\n\s*\n", text) if part.strip()]
    if not paragraphs:
        paragraphs = [text]
    blocks = excerpt_blocks(paragraphs)
    block_tokens = [token_counts(block) for block in blocks]
    document_frequency = {
        token: sum(1 for tokens in block_tokens if token in tokens)
        for token in query_tokens
    }
    block_count = max(len(blocks), 1)

    def score(index: int) -> float:
        tokens = block_tokens[index]
        total = 0.0
        for token in query_tokens:
            if token not in tokens:
                continue
            # Rare query terms are more useful than common terms, without a language-specific stopword list.
            rarity = block_count / max(document_frequency.get(token, 1), 1)
            total += rarity
        return total

    best_index = max(range(len(blocks)), key=score)
    best_score = score(best_index)
    if best_score == 0:
        return "", 0.0
    return blocks[best_index][:max_chars].strip(), best_score


def token_counts(text: str) -> dict[str, int]:
    counts: dict[str, int] = {}
    for token in tokenize(text):
        if len(token) <= 1:
            continue
        counts[token] = counts.get(token, 0) + 1
    return counts


def query_search_tokens(text: str) -> set[str]:
    tokens = {token for token in tokenize(text) if len(token) > 1}
    longer_tokens = {token for token in tokens if len(token) > 2}
    return longer_tokens or tokens


def excerpt_blocks(paragraphs: list[str]) -> list[str]:
    blocks = []
    for index, paragraph in enumerate(paragraphs):
        if is_markdown_heading(paragraph) and index + 1 < len(paragraphs):
            blocks.append(f"{paragraph}\n\n{paragraphs[index + 1]}")
        elif index > 0 and is_markdown_heading(paragraphs[index - 1]):
            blocks.append(f"{paragraphs[index - 1]}\n\n{paragraph}")
        else:
            blocks.append(paragraph)
    return blocks


def is_markdown_heading(paragraph: str) -> bool:
    return bool(re.match(r"^#{1,6}\s+\S+", paragraph.strip()))


def format_rows(rows: list[dict[str, Any]]) -> str:
    if not rows:
        return "No rows matched."
    return json.dumps(rows, indent=2, ensure_ascii=False)


def try_json(text: str) -> Any:
    try:
        return json.loads(text)
    except Exception:
        return text
