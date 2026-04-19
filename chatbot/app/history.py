from __future__ import annotations

import json
import sqlite3
import time
from pathlib import Path
from typing import Any

from app.config import resolve_path
from app.models import ChatRequest, ChatResponse


def history_enabled(config: dict[str, Any]) -> bool:
    return bool(config.get("history", {}).get("enabled", True))


def history_path(config: dict[str, Any]) -> Path:
    return resolve_path(config, config.get("history", {}).get("sqlite_path", "data/history.sqlite"))


def init_history_db(config: dict[str, Any]) -> None:
    path = history_path(config)
    path.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(path) as conn:
        create_history_table(conn)
        migrate_old_history_columns(conn)
        conn.execute("CREATE INDEX IF NOT EXISTS idx_chat_history_created_at ON chat_history(created_at)")


def create_history_table(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS chat_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at REAL NOT NULL,
            message TEXT NOT NULL,
            answer TEXT NOT NULL,
            source TEXT NOT NULL,
            provider TEXT,
            model TEXT,
            tool TEXT,
            retrieval_profile TEXT,
            use_rag INTEGER NOT NULL,
            use_local_files INTEGER NOT NULL,
            use_web_search INTEGER,
            metadata_json TEXT NOT NULL
        )
        """
    )


def migrate_old_history_columns(conn: sqlite3.Connection) -> None:
    columns = {row[1] for row in conn.execute("PRAGMA table_info(chat_history)").fetchall()}
    obsolete = {"rag" + "_only", "force" + "_llm"}
    if not obsolete.intersection(columns):
        return

    conn.execute("ALTER TABLE chat_history RENAME TO chat_history_old")
    create_history_table(conn)
    conn.execute(
        """
        INSERT INTO chat_history (
            id, created_at, message, answer, source, provider, model, tool,
            retrieval_profile, use_rag, use_local_files, use_web_search,
            metadata_json
        )
        SELECT
            id, created_at, message, answer, source, provider, model, tool,
            retrieval_profile, use_rag, use_local_files, use_web_search,
            metadata_json
        FROM chat_history_old
        """
    )
    conn.execute("DROP TABLE chat_history_old")


def record_chat(config: dict[str, Any], request: ChatRequest, response: ChatResponse) -> int | None:
    if not history_enabled(config):
        return None

    init_history_db(config)
    with sqlite3.connect(history_path(config)) as conn:
        cursor = conn.execute(
            """
            INSERT INTO chat_history (
                created_at,
                message,
                answer,
                source,
                provider,
                model,
                tool,
                retrieval_profile,
                use_rag,
                use_local_files,
                use_web_search,
                metadata_json
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                time.time(),
                request.message,
                response.answer,
                response.source,
                response.provider,
                response.model,
                response.tool,
                request.retrieval_profile,
                int(request.use_rag),
                int(request.use_local_files),
                None if request.use_web_search is None else int(request.use_web_search),
                json.dumps(response.metadata, ensure_ascii=False),
            ),
        )
        history_id = int(cursor.lastrowid)
    trim_history(config)
    return history_id


def list_history(config: dict[str, Any], limit: int = 50) -> list[dict[str, Any]]:
    init_history_db(config)
    limit = max(1, min(int(limit), 500))
    with sqlite3.connect(history_path(config)) as conn:
        conn.row_factory = sqlite3.Row
        rows = conn.execute(
            """
            SELECT id, created_at, message, answer, source, provider, model, tool,
                   retrieval_profile, use_rag, use_local_files,
                   use_web_search, metadata_json
            FROM chat_history
            ORDER BY created_at DESC
            LIMIT ?
            """,
            (limit,),
        ).fetchall()
    return [row_to_history_item(row) for row in rows]


def get_history_item(config: dict[str, Any], history_id: int) -> dict[str, Any] | None:
    init_history_db(config)
    with sqlite3.connect(history_path(config)) as conn:
        conn.row_factory = sqlite3.Row
        row = conn.execute(
            """
            SELECT id, created_at, message, answer, source, provider, model, tool,
                   retrieval_profile, use_rag, use_local_files,
                   use_web_search, metadata_json
            FROM chat_history
            WHERE id = ?
            """,
            (history_id,),
        ).fetchone()
    return row_to_history_item(row) if row else None


def clear_history(config: dict[str, Any]) -> int:
    init_history_db(config)
    with sqlite3.connect(history_path(config)) as conn:
        cursor = conn.execute("DELETE FROM chat_history")
        return int(cursor.rowcount)


def delete_history_item(config: dict[str, Any], history_id: int) -> bool:
    init_history_db(config)
    with sqlite3.connect(history_path(config)) as conn:
        cursor = conn.execute("DELETE FROM chat_history WHERE id = ?", (history_id,))
        return int(cursor.rowcount) > 0


def trim_history(config: dict[str, Any]) -> None:
    max_entries = int(config.get("history", {}).get("max_entries", 500))
    if max_entries <= 0:
        return
    with sqlite3.connect(history_path(config)) as conn:
        conn.execute(
            """
            DELETE FROM chat_history
            WHERE id NOT IN (
                SELECT id FROM chat_history
                ORDER BY created_at DESC
                LIMIT ?
            )
            """,
            (max_entries,),
        )


def row_to_history_item(row: sqlite3.Row) -> dict[str, Any]:
    metadata_json = row["metadata_json"] or "{}"
    try:
        metadata = json.loads(metadata_json)
    except json.JSONDecodeError:
        metadata = {"raw": metadata_json}
    return {
        "id": row["id"],
        "created_at": row["created_at"],
        "created_at_iso": time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime(row["created_at"])),
        "message": row["message"],
        "answer": row["answer"],
        "source": row["source"],
        "provider": row["provider"],
        "model": row["model"],
        "tool": row["tool"],
        "retrieval_profile": row["retrieval_profile"],
        "use_rag": bool(row["use_rag"]),
        "use_local_files": bool(row["use_local_files"]),
        "use_web_search": None if row["use_web_search"] is None else bool(row["use_web_search"]),
        "metadata": metadata,
    }
