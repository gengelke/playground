from __future__ import annotations

from pathlib import Path
from typing import Any, Optional

from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from app.chat import ChatService
from app.config import PROJECT_ROOT, load_config
from app.ingest import ingest_paths
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
