from __future__ import annotations

import argparse
import json
import os
import shlex
import sqlite3
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Any

from app.config import PROJECT_ROOT, load_config, resolve_path
from app.ingest import ignored_document_reason
from app.retrieval import configured_retrieval_profiles, sqlite_path


PLAYGROUND_ROOT = PROJECT_ROOT.parent


def main() -> None:
    parser = argparse.ArgumentParser(description="Whitelisted chatbot host commands.")
    subcommands = parser.add_subparsers(dest="command", required=True)
    subcommands.add_parser("time")
    subcommands.add_parser("statistics")
    subcommands.add_parser("list-docs")
    subcommands.add_parser("employees")
    add_employee = subcommands.add_parser("add-employee")
    add_employee.add_argument("message")
    delete_employee = subcommands.add_parser("delete-employee")
    delete_employee.add_argument("message")

    args = parser.parse_args()
    if args.command == "time":
        print(datetime.now().astimezone().isoformat(timespec="seconds"))
    elif args.command == "statistics":
        print_statistics()
    elif args.command == "list-docs":
        print_example_docs()
    elif args.command == "employees":
        print_employees()
    elif args.command == "add-employee":
        add_employee_from_message(args.message)
    elif args.command == "delete-employee":
        delete_employee_from_message(args.message)


def print_statistics() -> None:
    config = load_config()
    print("SQLite ingested documents")
    print_sqlite_documents(config)
    print()
    print("SQLite duplicate chunks")
    print_sqlite_duplicates(config)
    print()
    print("Qdrant collections")
    print_qdrant_collections(config)


def print_sqlite_documents(config: dict[str, Any]) -> None:
    path = sqlite_path(config)
    if not path.exists():
        print(f"No SQLite chunk store found at {path}")
        return

    with sqlite3.connect(path) as conn:
        conn.row_factory = sqlite3.Row
        rows = conn.execute(
            """
            SELECT
              source_path,
              COUNT(*) AS chunks,
              datetime(MIN(created_at), 'unixepoch', 'localtime') AS first_ingested,
              datetime(MAX(created_at), 'unixepoch', 'localtime') AS last_ingested
            FROM chunks
            GROUP BY source_path
            ORDER BY MAX(created_at) DESC, source_path
            """
        ).fetchall()

    if not rows:
        print("(no ingested SQLite chunks)")
        return
    print_table([dict(row) for row in rows], ["source_path", "chunks", "first_ingested", "last_ingested"])


def print_sqlite_duplicates(config: dict[str, Any]) -> None:
    path = sqlite_path(config)
    if not path.exists():
        print(f"No SQLite chunk store found at {path}")
        return

    with sqlite3.connect(path) as conn:
        conn.row_factory = sqlite3.Row
        rows = conn.execute(
            """
            SELECT source_path, chunk_index, COUNT(*) AS copies
            FROM chunks
            GROUP BY source_path, chunk_index
            HAVING COUNT(*) > 1
            ORDER BY copies DESC, source_path, chunk_index
            LIMIT 50
            """
        ).fetchall()

    if not rows:
        print("(no duplicate source_path/chunk_index rows)")
        return
    print_table([dict(row) for row in rows], ["source_path", "chunk_index", "copies"])


def print_qdrant_collections(config: dict[str, Any]) -> None:
    qdrant = config.get("qdrant", {})
    if not qdrant.get("enabled", False):
        print("Qdrant is disabled in config.")
        return

    base_url = str(qdrant.get("url", "http://localhost:6333")).rstrip("/")
    profiles = configured_retrieval_profiles(config)
    rows = []
    for profile in profiles.values():
        if profile.get("type") != "qdrant":
            continue
        collection = profile.get("collection") or qdrant.get("collection", "chatbot_chunks")
        data, error = fetch_json(f"{base_url}/collections/{collection}")
        if error:
            rows.append({"profile": profile.get("name"), "collection": collection, "points": "unavailable", "status": error})
            continue
        result = data.get("result", {})
        rows.append(
            {
                "profile": profile.get("name"),
                "collection": collection,
                "points": result.get("points_count", "?"),
                "status": result.get("status", "?"),
            }
        )

    if not rows:
        print("(no Qdrant profiles configured)")
        return
    print_table(rows, ["profile", "collection", "points", "status"])


def print_example_docs() -> None:
    config = load_config()
    source = next((item for item in config.get("local_files", []) if item.get("name") == "sample_docs"), None)
    path = resolve_path(config, source.get("path", "sample_docs") if source else "sample_docs")
    if not path.exists():
        print(f"Example docs directory not found: {path}")
        return
    for item in sorted(path.iterdir()):
        if item.is_file() and not ignored_document_reason(item):
            print(item.name)


def print_employees() -> None:
    with graphql_client() as client:
        response = client.query_employees()

    employees = getattr(response, "employees", response)
    if not employees:
        print("(no employees)")
        return
    rows = [normalize_graphql_model(employee) for employee in employees]
    print_table(rows, ["employeeId", "name", "surname", "role"])


def add_employee_from_message(message: str) -> None:
    name, surname, role = parse_add_employee_message(message)
    employee_id = int(time.time())
    with graphql_client() as client:
        response = client.mutation_add_employee(employee_id=employee_id, name=name, surname=surname, role=role)
    employee = getattr(response, "add_employee", response)
    print("Added employee")
    print_table([normalize_graphql_model(employee)], ["employeeId", "name", "surname", "role"])


def delete_employee_from_message(message: str) -> None:
    employee_id = parse_delete_employee_message(message)
    with graphql_client() as client:
        response = client.mutation_delete_employee(employee_id=employee_id)
    employee = getattr(response, "delete_employee", response)
    print("Deleted employee")
    print_table([normalize_graphql_model(employee)], ["employeeId", "name", "surname", "role"])


def parse_add_employee_message(message: str) -> tuple[str, str, str]:
    parts = shlex.split(message)
    if len(parts) < 5 or [part.lower() for part in parts[:2]] != ["add", "employee"]:
        raise SystemExit("Usage: Simon says add employee <name> <surname> <role>")
    name = parts[2]
    surname = parts[3]
    role = " ".join(parts[4:])
    if not name or not surname or not role:
        raise SystemExit("Usage: Simon says add employee <name> <surname> <role>")
    return name, surname, role


def parse_delete_employee_message(message: str) -> int:
    parts = shlex.split(message)
    if len(parts) != 3 or [part.lower() for part in parts[:2]] != ["delete", "employee"]:
        raise SystemExit("Usage: Simon says delete employee <employeeId>")
    try:
        return int(parts[2])
    except ValueError:
        raise SystemExit("employeeId must be an integer") from None


def graphql_client():
    library_path = generated_graphql_library_path()
    if not library_path:
        raise SystemExit("Generated GraphQL library not found. Run 'make -C api library-generate MODE=bare' or mount api/graphql-library/generated.")

    sys.path.insert(0, str(library_path))
    from fastapi_graphql_client import FastAPIGraphQLClient

    url = os.getenv("API_URL", "http://127.0.0.1:8000/graphql")
    username = os.getenv("FASTAPI_BASIC_AUTH_USERNAME", "admin")
    password = os.getenv("FASTAPI_BASIC_AUTH_PASSWORD", "password")
    return FastAPIGraphQLClient(url=url, headers={"Authorization": build_basic_auth_header(username, password)})


def generated_graphql_library_path() -> Path | None:
    candidates = [
        PLAYGROUND_ROOT / "api" / "graphql-library" / "generated",
        Path("/api/graphql-library/generated"),
    ]
    for path in candidates:
        if (path / "fastapi_graphql_client" / "__init__.py").is_file():
            return path
    return None


def build_basic_auth_header(username: str, password: str) -> str:
    import base64

    token = base64.b64encode(f"{username}:{password}".encode("utf-8")).decode("ascii")
    return f"Basic {token}"


def normalize_graphql_model(value: Any) -> dict[str, Any]:
    if hasattr(value, "model_dump"):
        return value.model_dump(by_alias=True)
    if isinstance(value, dict):
        return value
    if isinstance(value, tuple) and len(value) == 2 and isinstance(value[1], dict):
        return value[1]
    return {"employeeId": "", "name": str(value), "surname": "", "role": ""}


def fetch_json(url: str) -> tuple[dict[str, Any], str | None]:
    try:
        with urllib.request.urlopen(url, timeout=3) as response:
            return json.loads(response.read().decode("utf-8")), None
    except urllib.error.HTTPError as exc:
        return {}, f"HTTP {exc.code}"
    except Exception as exc:
        return {}, str(exc)


def print_table(rows: list[dict[str, Any]], columns: list[str]) -> None:
    widths = {
        column: max(len(column), *(len(str(row.get(column, ""))) for row in rows))
        for column in columns
    }
    header = "  ".join(column.ljust(widths[column]) for column in columns)
    print(header)
    print("  ".join("-" * widths[column] for column in columns))
    for row in rows:
        print("  ".join(str(row.get(column, "")).ljust(widths[column]) for column in columns))


if __name__ == "__main__":
    main()
