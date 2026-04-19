from __future__ import annotations

import hashlib
import math
import os
import re
from typing import Any

import requests


TOKEN_RE = re.compile(r"[A-Za-z0-9äöüÄÖÜß]+")
DEFAULT_VECTOR_SIZE = 96


def tokenize(text: str) -> list[str]:
    return [token.lower() for token in TOKEN_RE.findall(text.replace("_", " ").replace("-", " "))]


def embed_local_hash(text: str, size: int = DEFAULT_VECTOR_SIZE) -> list[float]:
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


def embed_text(config: dict[str, Any], embedding: dict[str, Any], text: str, input_type: str | None = None) -> tuple[list[float], dict[str, Any]]:
    provider = embedding.get("provider", "local_hash")
    model = embedding.get("model", "local-hash-96")
    if provider == "local_hash":
        size = int(embedding.get("vector_size", DEFAULT_VECTOR_SIZE))
        return embed_local_hash(text, size=size), {
            "provider": provider,
            "model": model,
            "vector_size": size,
        }
    if provider == "openai":
        return embed_openai(config, embedding, text)
    if provider == "ollama":
        return embed_ollama(config, embedding, text)
    if provider == "voyage":
        return embed_voyage(config, embedding, text, input_type=input_type)
    raise ValueError(f"unknown embedding provider: {provider}")


def embed_openai(config: dict[str, Any], embedding: dict[str, Any], text: str) -> tuple[list[float], dict[str, Any]]:
    openai = config.get("providers", {}).get("openai", {})
    api_key_env = embedding.get("api_key_env") or openai.get("api_key_env", "OPENAI_API_KEY")
    api_key = os.getenv(api_key_env)
    if not api_key:
        raise RuntimeError(f"OpenAI embedding API key environment variable is not set: {api_key_env}")

    model = embedding.get("model", "text-embedding-3-small")
    base_url = embedding.get("base_url", "https://api.openai.com/v1/embeddings")
    payload: dict[str, Any] = {"model": model, "input": text}
    if embedding.get("dimensions"):
        payload["dimensions"] = int(embedding["dimensions"])

    response = requests.post(
        base_url,
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        json=payload,
        timeout=float(embedding.get("timeout_seconds", openai.get("timeout_seconds", 60))),
    )
    response.raise_for_status()
    data = response.json()
    vector = data["data"][0]["embedding"]
    return vector, {
        "provider": "openai",
        "model": model,
        "vector_size": len(vector),
        "base_url": base_url,
    }


def embed_ollama(config: dict[str, Any], embedding: dict[str, Any], text: str) -> tuple[list[float], dict[str, Any]]:
    local = config.get("providers", {}).get("local", {})
    model = embedding.get("model", "nomic-embed-text")
    base_url = embedding.get("base_url", "http://localhost:11434/api/embeddings")
    response = requests.post(
        base_url,
        json={"model": model, "prompt": text},
        timeout=float(embedding.get("timeout_seconds", local.get("timeout_seconds", 180))),
    )
    response.raise_for_status()
    data = response.json()
    vector = data.get("embedding") or data.get("embeddings", [[]])[0]
    if not vector:
        raise RuntimeError("Ollama embedding response did not contain an embedding")
    return vector, {
        "provider": "ollama",
        "model": model,
        "vector_size": len(vector),
        "base_url": base_url,
    }


def embed_voyage(
    config: dict[str, Any],
    embedding: dict[str, Any],
    text: str,
    input_type: str | None = None,
) -> tuple[list[float], dict[str, Any]]:
    api_key_env = embedding.get("api_key_env", "VOYAGE_API_KEY")
    api_key = os.getenv(api_key_env)
    if not api_key:
        raise RuntimeError(f"Voyage embedding API key environment variable is not set: {api_key_env}")

    model = embedding.get("model", "voyage-3.5")
    base_url = embedding.get("base_url", "https://api.voyageai.com/v1/embeddings")
    payload: dict[str, Any] = {
        "model": model,
        "input": [text],
        "input_type": input_type or embedding.get("input_type", "document"),
    }
    if embedding.get("output_dimension"):
        payload["output_dimension"] = int(embedding["output_dimension"])

    response = requests.post(
        base_url,
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        json=payload,
        timeout=float(embedding.get("timeout_seconds", 60)),
    )
    response.raise_for_status()
    data = response.json()
    vector = data["data"][0]["embedding"]
    return vector, {
        "provider": "voyage",
        "model": model,
        "vector_size": len(vector),
        "base_url": base_url,
        "input_type": payload["input_type"],
    }
