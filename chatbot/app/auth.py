from __future__ import annotations

import hmac
import os
from typing import Any


def command_auth_required(config: dict[str, Any]) -> bool:
    return bool(config.get("auth", {}).get("command_auth_required", False))


def command_auth_status(config: dict[str, Any], provided_token: str | None) -> dict[str, Any]:
    if not command_auth_required(config):
        return {"authorized": True, "required": False}

    token_env = str(config.get("auth", {}).get("command_token_env", "CHATBOT_COMMAND_TOKEN"))
    expected_token = os.getenv(token_env, "")
    if not expected_token:
        return {
            "authorized": False,
            "required": True,
            "reason": "command token is not configured",
            "token_env": token_env,
        }

    if not provided_token:
        return {
            "authorized": False,
            "required": True,
            "reason": "missing bearer token",
            "token_env": token_env,
        }

    if not hmac.compare_digest(provided_token, expected_token):
        return {
            "authorized": False,
            "required": True,
            "reason": "invalid bearer token",
            "token_env": token_env,
        }

    return {"authorized": True, "required": True, "token_env": token_env}
