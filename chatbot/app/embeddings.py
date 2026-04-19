from __future__ import annotations

import hashlib
import math
import os
import re
from contextlib import contextmanager
from typing import Any

import requests


TOKEN_RE = re.compile(r"[A-Za-z0-9äöüÄÖÜß]+")
DEFAULT_VECTOR_SIZE = 96
TLS_CERT_ENV_VARS = ("SSL_CERT_FILE", "REQUESTS_CA_BUNDLE", "CURL_CA_BUNDLE", "PIP_CERT")


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
    raise ValueError(f"unknown embedding provider: {provider}")


@contextmanager
def sanitized_tls_env():
    removed: dict[str, str] = {}
    try:
        for name in TLS_CERT_ENV_VARS:
            value = os.getenv(name)
            if value and not os.path.isfile(value):
                removed[name] = value
                os.environ.pop(name, None)
        yield
    finally:
        for name, value in removed.items():
            os.environ[name] = value


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

    with sanitized_tls_env():
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
    base_url = embedding.get("base_url", "http://localhost:11434/api/embed")
    timeout = float(embedding.get("timeout_seconds", local.get("timeout_seconds", 180)))
    errors: list[str] = []
    for url, payload in ollama_embedding_attempts(base_url, model, text):
        try:
            with sanitized_tls_env():
                response = requests.post(url, json=payload, timeout=timeout)
            response.raise_for_status()
            data = response.json()
            vector = data.get("embedding") or data.get("embeddings", [[]])[0]
            if not vector:
                raise RuntimeError("Ollama embedding response did not contain an embedding")
            return vector, {
                "provider": "ollama",
                "model": model,
                "vector_size": len(vector),
                "base_url": url,
            }
        except Exception as exc:
            errors.append(f"{url}: {exc}")
            continue
    raise RuntimeError("; ".join(errors))


def ollama_embedding_attempts(base_url: str, model: str, text: str) -> list[tuple[str, dict[str, Any]]]:
    endpoints: list[tuple[str, dict[str, Any]]] = []

    def add(url: str, payload: dict[str, Any]) -> None:
        if not any(existing_url == url and existing_payload == payload for existing_url, existing_payload in endpoints):
            endpoints.append((url, payload))

    normalized = base_url.rstrip("/")
    if normalized.endswith("/api/embed"):
        add(normalized, {"model": model, "input": text})
        add(f"{normalized}dings", {"model": model, "prompt": text})
    elif normalized.endswith("/api/embeddings"):
        add(normalized, {"model": model, "prompt": text})
        add(normalized[: -len("dings")], {"model": model, "input": text})
    else:
        add(normalized, {"model": model, "input": text})
        add(normalized, {"model": model, "prompt": text})
        add(f"{normalized}/api/embed", {"model": model, "input": text})
        add(f"{normalized}/api/embeddings", {"model": model, "prompt": text})
    return endpoints
