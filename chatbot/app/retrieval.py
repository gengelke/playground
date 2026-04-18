from __future__ import annotations

import hashlib
import math
import re
import sqlite3
import time
from pathlib import Path
from typing import Any

from app.config import resolve_path
from app.models import RetrievedChunk


TOKEN_RE = re.compile(r"[A-Za-z0-9_\-äöüÄÖÜß]+")
DEFAULT_VECTOR_SIZE = 96
DEFAULT_MIN_QUERY_TOKENS = 2
DEFAULT_MIN_QUERY_CHARS = 4
DEFAULT_QDRANT_MIN_SCORE = 0.2


def tokenize(text: str) -> list[str]:
    return [token.lower() for token in TOKEN_RE.findall(text)]


def embed_text(text: str, size: int = DEFAULT_VECTOR_SIZE) -> list[float]:
    """Small deterministic embedding so RAG works without an external model."""
    vector = [0.0] * size
    for token in tokenize(text):
        digest = hashlib.sha256(token.encode("utf-8")).digest()
        index = int.from_bytes(digest[:4], "big") % size
        sign = 1.0 if digest[4] % 2 == 0 else -1.0
        vector[index] += sign

    length = math.sqrt(sum(value * value for value in vector))
    if not length:
        return vector
    return [value / length for value in vector]


def sqlite_path(config: dict[str, Any]) -> Path:
    return resolve_path(config, config.get("documents", {}).get("sqlite_path", "data/documents.sqlite"))


def init_document_db(config: dict[str, Any]) -> None:
    path = sqlite_path(config)
    path.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(path) as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS chunks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source_path TEXT NOT NULL,
                title TEXT,
                chunk_index INTEGER NOT NULL,
                text TEXT NOT NULL,
                created_at REAL NOT NULL
            )
            """
        )
        conn.execute("CREATE INDEX IF NOT EXISTS idx_chunks_source ON chunks(source_path)")


def reset_document_db(config: dict[str, Any]) -> None:
    init_document_db(config)
    with sqlite3.connect(sqlite_path(config)) as conn:
        conn.execute("DELETE FROM chunks")


def store_chunks(config: dict[str, Any], source_path: str, title: str, chunks: list[str]) -> list[int]:
    init_document_db(config)
    now = time.time()
    ids: list[int] = []
    with sqlite3.connect(sqlite_path(config)) as conn:
        for index, text in enumerate(chunks):
            cursor = conn.execute(
                """
                INSERT INTO chunks (source_path, title, chunk_index, text, created_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                (source_path, title, index, text, now),
            )
            ids.append(int(cursor.lastrowid))
    return ids


def search_sqlite_chunks(config: dict[str, Any], query: str, limit: int | None = None) -> list[RetrievedChunk]:
    init_document_db(config)
    document_config = config.get("documents", {})
    limit = limit or int(document_config.get("top_k", 4))
    query_tokens = set(tokenize(query))
    min_tokens = int(document_config.get("min_query_tokens", DEFAULT_MIN_QUERY_TOKENS))
    min_chars = int(document_config.get("min_query_chars", DEFAULT_MIN_QUERY_CHARS))
    min_score = float(document_config.get("min_score", 0.25))
    if len(query.strip()) < min_chars or len(query_tokens) < min_tokens:
        return []

    with sqlite3.connect(sqlite_path(config)) as conn:
        conn.row_factory = sqlite3.Row
        rows = conn.execute("SELECT id, source_path, chunk_index, text FROM chunks").fetchall()

    scored: list[RetrievedChunk] = []
    for row in rows:
        text_tokens = set(tokenize(row["text"]))
        if not text_tokens:
            continue
        overlap = len(query_tokens & text_tokens)
        if overlap == 0:
            continue
        score = overlap / max(len(query_tokens), 1)
        if score < min_score:
            continue
        scored.append(
            RetrievedChunk(
                text=row["text"],
                source_path=row["source_path"],
                chunk_id=row["id"],
                chunk_index=row["chunk_index"],
                score=score,
                retriever="sqlite",
            )
        )

    scored.sort(key=lambda chunk: chunk.score, reverse=True)
    return scored[:limit]


def qdrant_enabled(config: dict[str, Any]) -> bool:
    return bool(config.get("qdrant", {}).get("enabled", False))


def get_qdrant_client(config: dict[str, Any]):
    from qdrant_client import QdrantClient

    qdrant = config.get("qdrant", {})
    return QdrantClient(url=qdrant.get("url", "http://localhost:6333"), timeout=qdrant.get("timeout_seconds", 3))


def ensure_qdrant_collection(config: dict[str, Any]) -> bool:
    if not qdrant_enabled(config):
        return False

    from qdrant_client.models import Distance, VectorParams

    qdrant = config.get("qdrant", {})
    collection = qdrant.get("collection", "chatbot_chunks")
    size = int(qdrant.get("vector_size", DEFAULT_VECTOR_SIZE))
    client = get_qdrant_client(config)
    try:
        client.get_collection(collection)
        return True
    except Exception:
        client.create_collection(collection_name=collection, vectors_config=VectorParams(size=size, distance=Distance.COSINE))
        return True


def reset_qdrant_collection(config: dict[str, Any]) -> None:
    if not qdrant_enabled(config):
        return

    qdrant = config.get("qdrant", {})
    collection = qdrant.get("collection", "chatbot_chunks")
    try:
        client = get_qdrant_client(config)
        client.delete_collection(collection)
        ensure_qdrant_collection(config)
    except Exception:
        pass


def upsert_qdrant_chunks(config: dict[str, Any], chunk_ids: list[int], source_path: str, chunks: list[str]) -> bool:
    if not qdrant_enabled(config) or not chunk_ids:
        return False

    try:
        from qdrant_client.models import PointStruct

        qdrant = config.get("qdrant", {})
        collection = qdrant.get("collection", "chatbot_chunks")
        size = int(qdrant.get("vector_size", DEFAULT_VECTOR_SIZE))

        ensure_qdrant_collection(config)
        client = get_qdrant_client(config)
        points = []
        for chunk_id, text in zip(chunk_ids, chunks):
            points.append(
                PointStruct(
                    id=chunk_id,
                    vector=embed_text(text, size=size),
                    payload={"text": text, "source_path": source_path, "chunk_id": chunk_id},
                )
            )
        client.upsert(collection_name=collection, points=points)
        return True
    except Exception:
        return False


def search_qdrant(config: dict[str, Any], query: str, limit: int | None = None) -> list[RetrievedChunk]:
    if not qdrant_enabled(config):
        return []

    qdrant = config.get("qdrant", {})
    query_tokens = tokenize(query)
    min_tokens = int(qdrant.get("min_query_tokens", DEFAULT_MIN_QUERY_TOKENS))
    min_chars = int(qdrant.get("min_query_chars", DEFAULT_MIN_QUERY_CHARS))
    if len(query.strip()) < min_chars or len(query_tokens) < min_tokens:
        return []

    collection = qdrant.get("collection", "chatbot_chunks")
    size = int(qdrant.get("vector_size", DEFAULT_VECTOR_SIZE))
    limit = limit or int(config.get("documents", {}).get("top_k", 4))
    min_score = float(qdrant.get("min_score", DEFAULT_QDRANT_MIN_SCORE))

    try:
        ensure_qdrant_collection(config)
        client = get_qdrant_client(config)
        vector = embed_text(query, size=size)
        try:
            results = client.search(collection_name=collection, query_vector=vector, limit=limit)
        except AttributeError:
            results = client.query_points(collection_name=collection, query=vector, limit=limit).points
    except Exception:
        return []

    chunks: list[RetrievedChunk] = []
    for point in results:
        payload = point.payload or {}
        score = float(getattr(point, "score", 0.0))
        if score < min_score:
            continue
        text = str(payload.get("text", ""))
        if not text:
            continue
        chunks.append(
            RetrievedChunk(
                text=text,
                source_path=str(payload.get("source_path", "")),
                chunk_id=payload.get("chunk_id"),
                score=score,
                retriever="qdrant",
            )
        )
    return chunks


def hybrid_search(config: dict[str, Any], query: str, limit: int | None = None) -> list[RetrievedChunk]:
    limit = limit or int(config.get("documents", {}).get("top_k", 4))
    chunks = search_qdrant(config, query, limit=limit) + search_sqlite_chunks(config, query, limit=limit)
    seen: set[tuple[str, str]] = set()
    merged: list[RetrievedChunk] = []
    for chunk in sorted(chunks, key=lambda item: item.score, reverse=True):
        key = (chunk.source_path, chunk.text[:120])
        if key in seen:
            continue
        seen.add(key)
        merged.append(chunk)
        if len(merged) >= limit:
            break
    return merged
