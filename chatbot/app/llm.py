from __future__ import annotations

import os
from typing import Any

import requests

from app.models import LLMResult


def selected_provider_model(config: dict[str, Any], provider: str | None, model: str | None) -> tuple[str, str]:
    providers = config.get("providers", {})
    selected_provider = provider or providers.get("default_provider", "local")
    selected_model = (
        model
        or providers.get(selected_provider, {}).get("default_model")
        or providers.get("default_model")
        or "local-model"
    )
    return selected_provider, selected_model


def call_llm(
    config: dict[str, Any],
    message: str,
    provider: str | None = None,
    model: str | None = None,
    context: list[dict[str, str]] | None = None,
) -> LLMResult:
    selected_provider, selected_model = selected_provider_model(config, provider, model)
    prompt = build_prompt(message, context or [])

    if selected_provider == "openai":
        return call_openai(config, prompt, selected_model)
    if selected_provider == "anthropic":
        return call_anthropic(config, prompt, selected_model)
    if selected_provider == "local":
        return call_local(config, prompt, selected_model)

    return LLMResult(
        answer=f"Provider '{selected_provider}' is not configured.",
        provider=selected_provider,
        model=selected_model,
        metadata={"error": "unknown_provider"},
    )


def build_prompt(message: str, context: list[dict[str, str]]) -> str:
    if not context:
        return message

    context_text = "\n\n".join(f"[{item.get('source', 'context')}]\n{item.get('text', '')}" for item in context)
    return (
        "Answer the user using the local context when it is relevant. "
        "If the context is insufficient, say what is missing.\n\n"
        f"Local context:\n{context_text}\n\n"
        f"User question:\n{message}"
    )


def call_local(config: dict[str, Any], prompt: str, model: str) -> LLMResult:
    local = config.get("providers", {}).get("local", {})
    if local.get("enabled") is False:
        return LLMResult("Local LLM provider is disabled.", "local", model, {"error": "provider_disabled"})

    base_url = local.get("base_url", "http://localhost:11434/api/chat")
    timeout = float(local.get("timeout_seconds", 30))
    try:
        if "chat/completions" in base_url:
            response = requests.post(
                base_url,
                json={"model": model, "messages": [{"role": "user", "content": prompt}], "stream": False},
                timeout=timeout,
            )
            response.raise_for_status()
            data = response.json()
            answer = data["choices"][0]["message"]["content"]
        else:
            response = requests.post(
                base_url,
                json={"model": model, "messages": [{"role": "user", "content": prompt}], "stream": False},
                timeout=timeout,
            )
            response.raise_for_status()
            data = response.json()
            answer = data.get("message", {}).get("content") or data.get("response", "")
        return LLMResult(answer.strip(), "local", model, {"base_url": base_url})
    except Exception as exc:
        return LLMResult(
            "I do not have a deterministic answer, and the local LLM is unavailable.",
            "local",
            model,
            {"error": str(exc), "base_url": base_url},
        )


def call_openai(config: dict[str, Any], prompt: str, model: str) -> LLMResult:
    openai = config.get("providers", {}).get("openai", {})
    api_key = os.getenv(openai.get("api_key_env", "OPENAI_API_KEY"))
    if not api_key:
        return LLMResult("OpenAI is selected, but the API key environment variable is not set.", "openai", model, {"error": "missing_api_key"})

    base_url = openai.get("base_url", "https://api.openai.com/v1/chat/completions")
    try:
        response = requests.post(
            base_url,
            headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
            json={"model": model, "messages": [{"role": "user", "content": prompt}]},
            timeout=float(openai.get("timeout_seconds", 60)),
        )
        response.raise_for_status()
        data = response.json()
        answer = data["choices"][0]["message"]["content"]
        return LLMResult(answer.strip(), "openai", model, {"base_url": base_url})
    except Exception as exc:
        return LLMResult("OpenAI request failed.", "openai", model, {"error": str(exc), "base_url": base_url})


def call_anthropic(config: dict[str, Any], prompt: str, model: str) -> LLMResult:
    anthropic = config.get("providers", {}).get("anthropic", {})
    api_key = os.getenv(anthropic.get("api_key_env", "ANTHROPIC_API_KEY"))
    if not api_key:
        return LLMResult("Anthropic is selected, but the API key environment variable is not set.", "anthropic", model, {"error": "missing_api_key"})

    base_url = anthropic.get("base_url", "https://api.anthropic.com/v1/messages")
    try:
        response = requests.post(
            base_url,
            headers={
                "x-api-key": api_key,
                "anthropic-version": anthropic.get("api_version", "2023-06-01"),
                "Content-Type": "application/json",
            },
            json={
                "model": model,
                "max_tokens": int(anthropic.get("max_tokens", 800)),
                "messages": [{"role": "user", "content": prompt}],
            },
            timeout=float(anthropic.get("timeout_seconds", 60)),
        )
        response.raise_for_status()
        data = response.json()
        answer = "".join(part.get("text", "") for part in data.get("content", []) if part.get("type") == "text")
        return LLMResult(answer.strip(), "anthropic", model, {"base_url": base_url})
    except Exception as exc:
        return LLMResult("Anthropic request failed.", "anthropic", model, {"error": str(exc), "base_url": base_url})
