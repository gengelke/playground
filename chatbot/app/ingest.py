from __future__ import annotations

import argparse
from dataclasses import dataclass
import html
import re
import shutil
import zipfile
from pathlib import Path
from typing import Any

from app.config import load_config, resolve_path
from app.retrieval import concrete_ingest_profiles, reset_document_db, reset_qdrant_collection, store_chunks, upsert_qdrant_chunks_for_profile


TEXT_SUFFIXES = {".txt", ".md", ".rst", ".log", ".csv", ".json", ".yaml", ".yml", ".html", ".htm"}
PDF_SUFFIX = ".pdf"
SUPPORTED_SUFFIXES = TEXT_SUFFIXES | {".epub", PDF_SUFFIX}
IGNORED_SUFFIXES = {".bak", ".orig", ".rej", ".swp", ".swo", ".tmp", ".un~"}
IGNORED_NAMES = {".ds_store", "thumbs.db"}
DEFAULT_PDF_SECTION_CHARS = 5000
DEFAULT_PDF_MIN_SECTION_CHARS = 1200


@dataclass
class PdfPageText:
    page_number: int
    text: str


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
    if suffix == PDF_SUFFIX:
        raise ValueError("pdf files must be prepared before direct text reading")
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


def prepare_pdf_for_ingestion(config: dict[str, Any], path: Path) -> dict[str, Any]:
    pages = extract_pdf_pages(path)
    cleaned_pages, warnings = clean_pdf_pages(pages)
    sections = split_pdf_sections(config, cleaned_pages)
    if not sections:
        return {
            "source": relative_path(config, path),
            "prepared_files": [],
            "pages": len(pages),
            "warnings": warnings + ["no extractable text found"],
        }

    output_dir = resolve_path(config, config.get("documents", {}).get("prepared_path", "data/uploads/prepared")) / slugify(path.stem)
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    prepared_files = []
    for index, section in enumerate(sections, start=1):
        title = section["title"]
        section_path = output_dir / f"{index:03d}-{slugify(title)}.md"
        section_path.write_text(format_pdf_section(path, section), encoding="utf-8")
        prepared_files.append(section_path)

    return {
        "source": relative_path(config, path),
        "prepared_files": [relative_path(config, item) for item in prepared_files],
        "prepared_paths": prepared_files,
        "pages": len(pages),
        "sections": len(prepared_files),
        "warnings": warnings,
    }


def extract_pdf_pages(path: Path) -> list[PdfPageText]:
    try:
        from pypdf import PdfReader
    except ImportError as exc:
        raise RuntimeError("PDF ingestion requires the pypdf package.") from exc

    reader = PdfReader(str(path))
    pages = []
    for index, page in enumerate(reader.pages, start=1):
        pages.append(PdfPageText(page_number=index, text=page.extract_text() or ""))
    return pages


def clean_pdf_pages(pages: list[PdfPageText]) -> tuple[list[PdfPageText], list[str]]:
    repeated = repeated_pdf_lines(pages)
    warnings = []
    if repeated:
        warnings.append(f"removed {len(repeated)} repeated header/footer lines")

    cleaned = []
    empty_pages = 0
    for page in pages:
        text = clean_pdf_page_text(page.text, repeated)
        if not text:
            empty_pages += 1
            continue
        cleaned.append(PdfPageText(page_number=page.page_number, text=text))

    if empty_pages:
        warnings.append(f"skipped {empty_pages} empty pages")
    return cleaned, warnings


def repeated_pdf_lines(pages: list[PdfPageText]) -> set[str]:
    counts: dict[str, int] = {}
    for page in pages:
        lines = [line.strip() for line in page.text.splitlines() if line.strip()]
        candidates = {normalize_pdf_line(line) for line in lines[:3] + lines[-3:]}
        for key in candidates:
            if key:
                counts[key] = counts.get(key, 0) + 1

    threshold = max(2, int(len(pages) * 0.4))
    return {line for line, count in counts.items() if count >= threshold}


def clean_pdf_page_text(text: str, repeated_lines: set[str]) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"(\w)-\n(\w)", r"\1\2", text)

    kept = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            kept.append("")
            continue
        if normalize_pdf_line(stripped) in repeated_lines:
            continue
        if is_page_number_line(stripped):
            continue
        kept.append(stripped)

    return normalize_pdf_paragraphs("\n".join(kept))


def normalize_pdf_paragraphs(text: str) -> str:
    paragraphs = []
    current = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            if current:
                paragraphs.append(" ".join(current))
                current = []
            continue
        if is_probable_heading(stripped):
            if current:
                paragraphs.append(" ".join(current))
                current = []
            paragraphs.append(stripped)
            continue
        current.append(stripped)
    if current:
        paragraphs.append(" ".join(current))
    return "\n\n".join(paragraphs).strip()


def split_pdf_sections(config: dict[str, Any], pages: list[PdfPageText]) -> list[dict[str, Any]]:
    document_config = config.get("documents", {})
    max_chars = int(document_config.get("pdf_section_chars", DEFAULT_PDF_SECTION_CHARS))
    min_chars = int(document_config.get("pdf_min_section_chars", DEFAULT_PDF_MIN_SECTION_CHARS))
    sections = []
    current_lines: list[str] = []
    current_pages: list[int] = []
    current_title = "section"

    for page in pages:
        page_heading = f"Page {page.page_number}"
        for block in page.text.split("\n\n"):
            block = block.strip()
            if not block:
                continue

            if is_probable_heading(block) and len("\n".join(current_lines)) >= min_chars:
                # Heading encountered with enough content — save section and start a new one.
                text = "\n".join(current_lines).strip()
                if text:
                    sections.append({"title": current_title, "pages": current_pages[:], "text": text})
                current_lines, current_pages, current_title = [], [], block
            elif not current_lines:
                current_title = block if is_probable_heading(block) else page_heading

            if page.page_number not in current_pages:
                current_pages.append(page.page_number)
            current_lines.append(block)

            if len("\n".join(current_lines)) >= max_chars:
                # Section reached size limit — save and start fresh.
                text = "\n".join(current_lines).strip()
                if text:
                    sections.append({"title": current_title, "pages": current_pages[:], "text": text})
                current_lines, current_pages, current_title = [], [], "section"

    # Save whatever remains.
    text = "\n".join(current_lines).strip()
    if text:
        sections.append({"title": current_title, "pages": current_pages[:], "text": text})

    return sections


def format_pdf_section(source_path: Path, section: dict[str, Any]) -> str:
    pages = ", ".join(str(page) for page in section.get("pages", []))
    return (
        f"# {section.get('title') or source_path.stem}\n\n"
        f"Source PDF: {source_path.name}\n\n"
        f"Pages: {pages or 'unknown'}\n\n"
        f"{section.get('text', '').strip()}\n"
    )


def normalize_pdf_line(line: str) -> str:
    return re.sub(r"\s+", " ", line.strip().lower())


def is_page_number_line(line: str) -> bool:
    return bool(re.match(r"^(?:page\s*)?\d+(?:\s*/\s*\d+)?$", line.strip(), flags=re.IGNORECASE))


def is_probable_heading(line: str) -> bool:
    stripped = line.strip()
    if len(stripped) < 4 or len(stripped) > 100:
        return False
    if stripped.endswith((".", ",", ";", ":")) and not re.match(r"^\d+(?:\.\d+)*\s+", stripped):
        return False
    if re.match(r"^(chapter|part|section|appendix)\s+\w+", stripped, flags=re.IGNORECASE):
        return True
    if re.match(r"^\d+(?:\.\d+)*\s+\S+", stripped):
        return True
    letters = [char for char in stripped if char.isalpha()]
    if letters and sum(char.isupper() for char in letters) / len(letters) > 0.75:
        return True
    words = stripped.split()
    title_words = sum(1 for word in words if word[:1].isupper())
    return len(words) <= 8 and title_words >= max(2, len(words) - 1)


def slugify(value: str) -> str:
    value = re.sub(r"[^A-Za-z0-9._-]+", "-", value.strip().lower())
    return value.strip("-._") or "document"


def iter_input_files(paths: list[Path]) -> list[Path]:
    files: list[Path] = []
    for path in paths:
        if path.is_dir():
            files.extend(item for item in path.rglob("*") if item.is_file())
        elif path.is_file():
            files.append(path)
    return files


def ingest_paths(config: dict[str, Any], paths: list[str | Path], reset: bool = False, profiles: list[str] | None = None) -> dict[str, Any]:
    selected_profiles = concrete_ingest_profiles(config, profiles)
    if reset:
        reset_document_db(config)
        for profile in selected_profiles:
            if profile.get("type") == "qdrant":
                reset_qdrant_collection(config, profile["name"])

    document_config = config.get("documents", {})
    chunk_size = int(document_config.get("chunk_size", 900))
    overlap = int(document_config.get("chunk_overlap", 150))
    resolved = [resolve_path(config, path) for path in paths]

    ingested = []
    skipped = []
    prepared = []
    for path in iter_input_files(resolved):
        try:
            if path.suffix.lower() == PDF_SUFFIX:
                preparation = prepare_pdf_for_ingestion(config, path)
                prepared.append({key: value for key, value in preparation.items() if key != "prepared_paths"})
                prepared_paths = preparation.get("prepared_paths", [])
                if not prepared_paths:
                    skipped.append({"path": str(path), "reason": "pdf had no extractable text"})
                    continue
                for prepared_path in prepared_paths:
                    ingest_one_path(config, prepared_path, chunk_size, overlap, selected_profiles, ingested, skipped)
                continue

            ingest_one_path(config, path, chunk_size, overlap, selected_profiles, ingested, skipped)
        except Exception as exc:
            skipped.append({"path": str(path), "reason": str(exc)})

    result = {
        "ingested": ingested,
        "skipped": skipped,
        "profiles": [profile["name"] for profile in selected_profiles],
    }
    if prepared:
        result["prepared"] = prepared
    return result


def ingest_one_path(
    config: dict[str, Any],
    path: Path,
    chunk_size: int,
    overlap: int,
    profiles: list[dict[str, Any]],
    ingested: list[dict[str, Any]],
    skipped: list[dict[str, Any]],
) -> None:
    try:
        text = read_document(path)
        chunks = chunk_text(text, chunk_size=chunk_size, overlap=overlap)
        if not chunks:
            skipped.append({"path": str(path), "reason": "no text"})
            return
        relative = relative_path(config, path)
        ids = store_chunks(config, relative, path.name, chunks)
        profile_results: dict[str, Any] = {"sqlite": {"stored": True, "chunks": len(chunks)}}
        qdrant_written = False
        for profile in profiles:
            if profile.get("type") != "qdrant":
                continue
            result = upsert_qdrant_chunks_for_profile(config, profile["name"], ids, relative, chunks)
            profile_results[profile["name"]] = result
            qdrant_written = qdrant_written or bool(result.get("stored"))
        ingested.append({"path": relative, "chunks": len(chunks), "qdrant": qdrant_written, "profile_results": profile_results})
    except Exception as exc:
        skipped.append({"path": str(path), "reason": str(exc)})


def relative_path(config: dict[str, Any], path: Path) -> str:
    root = Path(config.get("_project_root", ""))
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def main() -> None:
    parser = argparse.ArgumentParser(description="Ingest local documents into SQLite and optional Qdrant.")
    parser.add_argument("paths", nargs="+", help="Files or directories to ingest.")
    parser.add_argument("--config", default=None, help="Path to config.yml.")
    parser.add_argument("--reset", action="store_true", help="Clear existing chunks before ingesting.")
    parser.add_argument("--profiles", default=None, help="Comma-separated retrieval profiles to ingest, for example sqlite,qdrant_openai.")
    args = parser.parse_args()

    config = load_config(args.config)
    profiles = split_profiles(args.profiles)
    result = ingest_paths(config, args.paths, reset=args.reset, profiles=profiles)
    for item in result.get("prepared", []):
        print(f"prepared {item['source']} sections={item.get('sections', 0)} pages={item.get('pages', 0)}")
        for warning in item.get("warnings", []):
            print(f"warning {item['source']}: {warning}")
    for item in result["ingested"]:
        print(f"ingested {item['path']} chunks={item['chunks']} qdrant={item['qdrant']}")
    for item in result["skipped"]:
        print(f"skipped {item['path']}: {item['reason']}")


def split_profiles(value: str | None) -> list[str] | None:
    if not value:
        return None
    return [item.strip() for item in value.split(",") if item.strip()]


if __name__ == "__main__":
    main()
