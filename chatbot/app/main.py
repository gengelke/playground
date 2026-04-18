from __future__ import annotations

from pathlib import Path
from typing import Any, Optional

from fastapi import FastAPI, File, Form, UploadFile
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from app.chat import ChatService
from app.config import PROJECT_ROOT, load_config
from app.ingest import ingest_paths, ignored_document_reason
from app.models import ChatRequest


config = load_config()
service = ChatService(config)
app = FastAPI(title="Local-first Chatbot", version="0.1.0")
app.mount("/static", StaticFiles(directory=PROJECT_ROOT / "app" / "static"), name="static")


class ChatApiRequest(BaseModel):
    message: str = Field(min_length=1)
    provider: Optional[str] = None
    model: Optional[str] = None
    use_rag: bool = True
    rag_only: bool = False
    use_local_files: bool = False
    use_web_search: Optional[bool] = None
    force_llm: bool = False


class IngestApiRequest(BaseModel):
    paths: list[str]
    reset: bool = False


@app.get("/")
def index() -> FileResponse:
    return FileResponse(Path(PROJECT_ROOT) / "app" / "static" / "index.html")


@app.get("/health")
def health() -> dict[str, Any]:
    return {"status": "ok"}


@app.post("/api/chat")
def chat(request: ChatApiRequest) -> dict[str, Any]:
    response = service.answer(
        ChatRequest(
            message=request.message,
            provider=request.provider,
            model=request.model,
            use_rag=request.use_rag,
            rag_only=request.rag_only,
            use_local_files=request.use_local_files,
            use_web_search=request.use_web_search,
            force_llm=request.force_llm,
        )
    )
    return {
        "answer": response.answer,
        "source": response.source,
        "provider": response.provider,
        "model": response.model,
        "tool": response.tool,
        "metadata": response.metadata,
    }


@app.post("/api/ingest")
def ingest(request: IngestApiRequest) -> dict[str, Any]:
    return ingest_paths(config, request.paths, reset=request.reset)


@app.post("/api/ingest/files")
async def ingest_uploaded_files(files: list[UploadFile] = File(...), reset: bool = Form(False)) -> dict[str, Any]:
    upload_dir = Path(PROJECT_ROOT) / "data" / "uploads"
    upload_dir.mkdir(parents=True, exist_ok=True)

    saved_paths = []
    skipped = []
    for upload in files:
        filename = safe_upload_name(upload.filename or "upload.txt")
        path = upload_dir / filename
        reason = ignored_document_reason(path)
        if reason:
            skipped.append({"path": filename, "reason": reason})
            continue

        content = await upload.read()
        path.write_bytes(content)
        saved_paths.append(path)

    result = ingest_paths(config, saved_paths, reset=reset) if saved_paths else {"ingested": [], "skipped": []}
    result["skipped"] = skipped + result.get("skipped", [])
    result["uploaded"] = [str(path.relative_to(PROJECT_ROOT)) for path in saved_paths]
    return result


def safe_upload_name(name: str) -> str:
    cleaned = Path(name).name.strip().replace(" ", "_")
    allowed = []
    for char in cleaned:
        allowed.append(char if char.isalnum() or char in {"-", "_", "."} else "_")
    result = "".join(allowed).strip("._")
    return result or "upload.txt"
