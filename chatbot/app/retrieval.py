from __future__ import annotations

import sqlite3
import time
from pathlib import Path
from typing import Any

from app.config import resolve_path
from app.embeddings import embed_text as embed_with_profile, tokenize
from app.models import RetrievedChunk


def configured_retrieval_profiles(config: dict[str, Any]) -> dict[str, dict[str, Any]]:
    retrieval = config.get("retrieval", {})
    configured = retrieval.get("profiles")
    if isinstance(configured, dict):
        return {name: {"name": name, **profile} for name, profile in configured.items()}
    if isinstance(configured, list):
        return {profile["name"]: profile for profile in configured if profile.get("name")}

    return {
        "sqlite": {"name": "sqlite", "type": "sqlite"},
        "qdrant_openai": {
            "name": "qdrant_openai",
            "type": "qdrant",
            "collection": "chatbot_chunks_openai",
            "embedding": {
                "provider": "openai",
                "model": "text-embedding-3-small",
                "vector_size": 1536,
            },
        },
    }



def default_retrieval_profile(config: dict[str, Any]) -> str:
    return config.get("retrieval", {}).get("default_profile", "sqlite")


def default_ingest_profiles(config: dict[str, Any]) -> list[str]:
    configured = config.get("retrieval", {}).get("ingest_profiles")
    if configured:
        return list(configured)
    return ["sqlite"]


def get_retrieval_profile(config: dict[str, Any], name: str | None = None) -> dict[str, Any]:
    profiles = configured_retrieval_profiles(config)
    selected = name or default_retrieval_profile(config)
    if selected not in profiles:
        raise ValueError(f"unknown retrieval profile: {selected}")
    return profiles[selected]


def concrete_ingest_profiles(config: dict[str, Any], names: list[str] | None = None) -> list[dict[str, Any]]:
    profiles = configured_retrieval_profiles(config)
    selected_names = names or default_ingest_profiles(config)
    selected: list[dict[str, Any]] = []
    seen: set[str] = set()
    for name in selected_names:
        profile = profiles.get(name)
        if not profile:
            raise ValueError(f"unknown retrieval profile: {name}")
        if name in seen:
            continue
        seen.add(name)
        selected.append(profile)
    return selected


def qdrant_profile_details(config: dict[str, Any], profile: dict[str, Any] | None = None) -> tuple[str, dict[str, Any], int]:
    qdrant = config.get("qdrant", {})
    profile = profile or get_retrieval_profile(config, "qdrant_openai")
    embedding = profile.get("embedding", {})
    collection = profile.get("collection") or qdrant.get("collection", "chatbot_chunks")
    size = int(embedding.get("vector_size", qdrant.get("vector_size", 1536)))
    return collection, embedding, size


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
    if not query_tokens:
        return []

    with sqlite3.connect(sqlite_path(config)) as conn:
        conn.row_factory = sqlite3.Row
        rows = conn.execute("SELECT id, source_path, title, chunk_index, text FROM chunks").fetchall()

    scored: list[RetrievedChunk] = []
    for row in rows:
        text_tokens = set(tokenize(row["text"]))
        metadata_tokens = set(tokenize(f"{row['source_path']} {row['title'] or ''}"))
        searchable_tokens = text_tokens | metadata_tokens
        if not searchable_tokens:
            continue
        text_overlap = len(query_tokens & text_tokens)
        metadata_overlap = len(query_tokens & metadata_tokens)
        if text_overlap == 0 and metadata_overlap == 0:
            continue
        score = (text_overlap + metadata_overlap) / max(len(query_tokens), 1)
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


def ensure_qdrant_collection(config: dict[str, Any], profile: dict[str, Any] | None = None) -> bool:
    if not qdrant_enabled(config):
        return False

    from qdrant_client.models import Distance, VectorParams

    collection, _embedding, size = qdrant_profile_details(config, profile)
    client = get_qdrant_client(config)
    try:
        client.get_collection(collection)
        return True
    except Exception:
        client.create_collection(collection_name=collection, vectors_config=VectorParams(size=size, distance=Distance.COSINE))
        return True


def reset_qdrant_collection(config: dict[str, Any], profile_name: str | None = None) -> None:
    if not qdrant_enabled(config):
        return

    profile = get_retrieval_profile(config, profile_name or default_retrieval_profile(config))
    collection, _embedding, _size = qdrant_profile_details(config, profile)
    try:
        client = get_qdrant_client(config)
        client.delete_collection(collection)
        ensure_qdrant_collection(config, profile)
    except Exception:
        pass


def upsert_qdrant_chunks_for_profile(
    config: dict[str, Any],
    profile_name: str,
    chunk_ids: list[int],
    source_path: str,
    chunks: list[str],
) -> dict[str, Any]:
    if not qdrant_enabled(config) or not chunk_ids:
        return {"profile": profile_name, "stored": False, "reason": "qdrant disabled or no chunks"}

    try:
        from qdrant_client.models import PointStruct

        profile = get_retrieval_profile(config, profile_name)
        if profile.get("type") != "qdrant":
            return {"profile": profile_name, "stored": False, "reason": "not a qdrant profile"}
        collection, embedding, expected_size = qdrant_profile_details(config, profile)

        ensure_qdrant_collection(config, profile)
        client = get_qdrant_client(config)
        points = []
        embedding_metadata = None
        for chunk_id, text in zip(chunk_ids, chunks):
            embedding_text = f"{source_path}\n{text}"
            vector, metadata = embed_with_profile(config, embedding, embedding_text)
            embedding_metadata = metadata
            if len(vector) != expected_size:
                raise RuntimeError(
                    f"embedding vector size {len(vector)} does not match configured size {expected_size} for {profile_name}"
                )
            points.append(
                PointStruct(
                    id=chunk_id,
                    vector=vector,
                    payload={"text": text, "source_path": source_path, "chunk_id": chunk_id},
                )
            )
        client.upsert(collection_name=collection, points=points)
        return {
            "profile": profile_name,
            "stored": True,
            "collection": collection,
            "embedding": embedding_metadata or embedding,
        }
    except Exception as exc:
        return {"profile": profile_name, "stored": False, "error": str(exc)}


def search_qdrant(config: dict[str, Any], query: str, limit: int | None = None, profile_name: str | None = None) -> list[RetrievedChunk]:
    if not qdrant_enabled(config):
        return []

    profile = get_retrieval_profile(config, profile_name or default_retrieval_profile(config))
    if profile.get("type") != "qdrant":
        return []
    if not tokenize(query):
        return []

    collection, embedding, _expected_size = qdrant_profile_details(config, profile)
    limit = limit or int(config.get("documents", {}).get("top_k", 4))

    try:
        ensure_qdrant_collection(config, profile)
        client = get_qdrant_client(config)
        vector, _metadata = embed_with_profile(config, embedding, query)
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
        text = str(payload.get("text", ""))
        if not text:
            continue
        chunks.append(
            RetrievedChunk(
                text=text,
                source_path=str(payload.get("source_path", "")),
                chunk_id=payload.get("chunk_id"),
                score=score,
                retriever=f"qdrant:{profile.get('name', profile_name or 'qdrant')}",
            )
        )
    return chunks[:limit]


def search_retrieval_profile(config: dict[str, Any], query: str, profile_name: str | None = None, limit: int | None = None) -> list[RetrievedChunk]:
    profile = get_retrieval_profile(config, profile_name)
    profile_type = profile.get("type")
    if profile_type == "sqlite":
        return search_sqlite_chunks(config, query, limit=limit)
    if profile_type == "qdrant":
        return search_qdrant(config, query, limit=limit, profile_name=profile["name"])
    raise ValueError(f"unsupported retrieval profile type: {profile_type}")
