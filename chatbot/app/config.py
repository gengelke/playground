from __future__ import annotations

import os
import re
from copy import deepcopy
from pathlib import Path
from typing import Any

import yaml


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG_PATH = PROJECT_ROOT / "config" / "config.yml"
ENV_DEFAULT_RE = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*):-([^}]*)\}")


def load_config(config_path: str | Path | None = None) -> dict[str, Any]:
    path = Path(config_path or os.getenv("CHATBOT_CONFIG", DEFAULT_CONFIG_PATH))
    with path.open("r", encoding="utf-8") as handle:
        config = yaml.safe_load(handle) or {}

    config = expand_env_values(config)
    apply_env_overrides(config)
    config["_config_path"] = str(path)
    config["_project_root"] = str(PROJECT_ROOT)
    return config


def expand_env_values(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: expand_env_values(item) for key, item in value.items()}
    if isinstance(value, list):
        return [expand_env_values(item) for item in value]
    if isinstance(value, str):
        return expand_env_string(value)
    return value


def expand_env_string(value: str) -> str:
    def replace(match: re.Match[str]) -> str:
        name, default = match.group(1), match.group(2)
        return os.getenv(name, default)

    return os.path.expandvars(ENV_DEFAULT_RE.sub(replace, value))


def apply_env_overrides(config: dict[str, Any]) -> None:
    providers = config.setdefault("providers", {})
    if os.getenv("CHATBOT_DEFAULT_PROVIDER"):
        providers["default_provider"] = os.environ["CHATBOT_DEFAULT_PROVIDER"]
    if os.getenv("CHATBOT_DEFAULT_MODEL"):
        providers["default_model"] = os.environ["CHATBOT_DEFAULT_MODEL"]

    qdrant = config.setdefault("qdrant", {})
    if os.getenv("QDRANT_URL"):
        qdrant["url"] = os.environ["QDRANT_URL"]


def resolve_path(config: dict[str, Any], path_value: str | Path) -> Path:
    path = Path(str(path_value))
    if path.is_absolute():
        return path
    return Path(config.get("_project_root", PROJECT_ROOT)) / path


def copy_config(config: dict[str, Any]) -> dict[str, Any]:
    return deepcopy(config)
