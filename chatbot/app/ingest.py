from __future__ import annotations

import argparse
import html
import re
import zipfile
from pathlib import Path
from typing import Any

from app.config import load_config, resolve_path
from app.retrieval import reset_document_db, reset_qdrant_collection, store_chunks, upsert_qdrant_chunks


TEXT_SUFFIXES = {".txt", ".md", ".rst", ".log", ".csv", ".json", ".yaml", ".yml", ".html", ".htm"}
SUPPORTED_SUFFIXES = TEXT_SUFFIXES | {".epub"}
IGNORED_SUFFIXES = {".bak", ".orig", ".rej", ".swp", ".swo", ".tmp", ".un~"}
IGNORED_NAMES = {".ds_store", "thumbs.db"}


def ignored_document_reason(path: Path) -> str | None:
    name = path.name.lower()
    suffix = path.suffix.lower()
    if name in IGNORED_NAMES:
        return "ignored system file"
    if name.endswith("~") or suffix in IGNORED_SUFFIXES:
        return "ignored temporary/editor file"
    if suffix not in SUPPORTED_SUFFIXES:
        return f"unsupported file type: {suffix or 'no suffix'}"
    return None


def read_document(path: Path) -> str:
    reason = ignored_document_reason(path)
    if reason:
        raise ValueError(reason)

    suffix = path.suffix.lower()
    if suffix == ".epub":
        return read_epub_text(path)
    if suffix in TEXT_SUFFIXES:
        return path.read_text(encoding="utf-8", errors="ignore")
    raise ValueError(f"unsupported file type: {suffix or 'no suffix'}")


def read_epub_text(path: Path) -> str:
    parts: list[str] = []
    with zipfile.ZipFile(path) as archive:
        for name in archive.namelist():
            if not name.lower().endswith((".html", ".xhtml", ".htm")):
                continue
            raw = archive.read(name).decode("utf-8", errors="ignore")
            parts.append(strip_html(raw))
    return "\n\n".join(parts)


def strip_html(text: str) -> str:
    text = re.sub(r"<script.*?</script>", " ", text, flags=re.IGNORECASE | re.DOTALL)
    text = re.sub(r"<style.*?</style>", " ", text, flags=re.IGNORECASE | re.DOTALL)
    text = re.sub(r"<[^>]+>", " ", text)
    return html.unescape(re.sub(r"\s+", " ", text)).strip()


def chunk_text(text: str, chunk_size: int = 900, overlap: int = 150) -> list[str]:
    cleaned = re.sub(r"\s+", " ", text).strip()
    if not cleaned:
        return []

    chunks: list[str] = []
    start = 0
    while start < len(cleaned):
        end = min(start + chunk_size, len(cleaned))
        chunks.append(cleaned[start:end].strip())
        if end == len(cleaned):
            break
        start = max(end - overlap, start + 1)
    return chunks


def iter_input_files(paths: list[Path]) -> list[Path]:
    files: list[Path] = []
    for path in paths:
        if path.is_dir():
            files.extend(item for item in path.rglob("*") if item.is_file())
        elif path.is_file():
            files.append(path)
    return files


def ingest_paths(config: dict[str, Any], paths: list[str | Path], reset: bool = False) -> dict[str, Any]:
    if reset:
        reset_document_db(config)
        reset_qdrant_collection(config)

    document_config = config.get("documents", {})
    chunk_size = int(document_config.get("chunk_size", 900))
    overlap = int(document_config.get("chunk_overlap", 150))
    resolved = [resolve_path(config, path) for path in paths]

    ingested = []
    skipped = []
    for path in iter_input_files(resolved):
        try:
            text = read_document(path)
            chunks = chunk_text(text, chunk_size=chunk_size, overlap=overlap)
            if not chunks:
                skipped.append({"path": str(path), "reason": "no text"})
                continue
            relative = str(path.relative_to(config.get("_project_root"))) if str(path).startswith(config.get("_project_root", "")) else str(path)
            ids = store_chunks(config, relative, path.name, chunks)
            qdrant_written = upsert_qdrant_chunks(config, ids, relative, chunks)
            ingested.append({"path": relative, "chunks": len(chunks), "qdrant": qdrant_written})
        except Exception as exc:
            skipped.append({"path": str(path), "reason": str(exc)})

    return {"ingested": ingested, "skipped": skipped}


def main() -> None:
    parser = argparse.ArgumentParser(description="Ingest local documents into SQLite and optional Qdrant.")
    parser.add_argument("paths", nargs="+", help="Files or directories to ingest.")
    parser.add_argument("--config", default=None, help="Path to config.yml.")
    parser.add_argument("--reset", action="store_true", help="Clear existing chunks before ingesting.")
    args = parser.parse_args()

    config = load_config(args.config)
    result = ingest_paths(config, args.paths, reset=args.reset)
    for item in result["ingested"]:
        print(f"ingested {item['path']} chunks={item['chunks']} qdrant={item['qdrant']}")
    for item in result["skipped"]:
        print(f"skipped {item['path']}: {item['reason']}")


if __name__ == "__main__":
    main()
