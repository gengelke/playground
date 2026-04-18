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


def run_configured_tool(config: dict[str, Any], message: str) -> dict[str, Any] | None:
    for tool in config.get("tools", []):
        match = tool.get("match", {})
        if not first_match(message, match.get("exact"), match.get("patterns")):
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


def search_local_files(config: dict[str, Any], message: str) -> dict[str, Any] | None:
    for source in config.get("local_files", []):
        if source.get("enabled") is False:
            continue
        if not first_match(message, source.get("match", {}).get("exact"), source.get("match", {}).get("patterns")):
            continue

        path = resolve_path(config, source.get("path", ""))
        files = [path]
        if path.is_dir():
            files = [item for item in path.rglob("*") if item.is_file()]

        excerpts = []
        for file_path in files[: int(source.get("max_files", 10))]:
            try:
                text = read_document(file_path)
            except Exception:
                continue
            excerpt = best_excerpt(text, message, int(source.get("max_chars", 1200)))
            if excerpt:
                excerpts.append({"path": str(file_path), "text": excerpt})
        if excerpts:
            return {"name": source.get("name"), "matches": excerpts}
    return None


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
    if not text.strip():
        return ""
    query_tokens = set(tokenize(query))
    if not query_tokens:
        return text[:max_chars].strip()

    paragraphs = [part.strip() for part in re.split(r"\n\s*\n", text) if part.strip()]
    if not paragraphs:
        paragraphs = [text]

    def score(paragraph: str) -> int:
        return len(query_tokens & set(tokenize(paragraph)))

    best = max(paragraphs, key=score)
    if score(best) == 0:
        best = text
    return best[:max_chars].strip()


def format_rows(rows: list[dict[str, Any]]) -> str:
    if not rows:
        return "No rows matched."
    return json.dumps(rows, indent=2, ensure_ascii=False)


def try_json(text: str) -> Any:
    try:
        return json.loads(text)
    except Exception:
        return text

