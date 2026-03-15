#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path


EXAMPLE_CLIENT_DIR   = Path(__file__).resolve().parent
API_DIR              = EXAMPLE_CLIENT_DIR.parent
GRAPHQL_LIBRARY      = API_DIR / "graphql-library"
GRAPHQL_LIBRARY_VENV = GRAPHQL_LIBRARY / ".venv" / "bin" / "python"
GRAPHQL_LIBRARY_CODE = GRAPHQL_LIBRARY / "generated"
DEFAULT_GRAPHQL_URL  = os.getenv("API_URL", "http://127.0.0.1:8000/graphql")


FORCE_COLOR = os.getenv("FORCE_COLOR", "").strip().lower()
USE_COLOR = (
    os.getenv("NO_COLOR") is None
    and (
        sys.stdout.isatty()
        or sys.stderr.isatty()
        or FORCE_COLOR in {"1", "true", "yes", "on"}
    )
)

RED      = "\033[38;5;196m" if USE_COLOR else ""
SOFT_RED = "\033[38;5;203m" if USE_COLOR else ""
GREEN    = "\033[38;5;46m"  if USE_COLOR else ""
GREEN2   = "\033[32m"       if USE_COLOR else ""
CYAN     = "\033[38;5;51m"  if USE_COLOR else ""
GREY     = "\033[38;5;245m" if USE_COLOR else ""
RESET    = "\033[0m"        if USE_COLOR else ""


LOGO = r"""
▄▖         ▜     ▄▖  ▗ ▌       ▄▖▜ ▘    ▗
▙▖▚▘▀▌▛▛▌▛▌▐ █▌  ▙▌▌▌▜▘▛▌▛▌▛▌  ▌ ▐ ▌█▌▛▌▜▘
▙▖▞▖█▌▌▌▌▙▌▐▖▙▖  ▌ ▙▌▐▖▌▌▙▌▌▌  ▙▖▐▖▌▙▖▌▌▐▖
         ▌         ▄▌
"""


class ColorParser(argparse.ArgumentParser):
    def format_help(self) -> str:
        return colorize(super().format_help(), CYAN)

    def error(self, message: str) -> None:
        self.print_usage(sys.stderr)
        fail(f"argument error: {message}", color=SOFT_RED)


def colorize(text: str, color: str) -> str:
    if not USE_COLOR or not text:
        return text
    return f"{color}{text}{RESET}"


def fail(message: str, color: str = RED) -> None:
    print(colorize(message, color), file=sys.stderr)
    raise SystemExit(1)


def print_step(message: str) -> None:
    print(f"\n{CYAN}⭐ {message}{RESET}")


def print_success(payload: object) -> None:
    print(f"\n{GREEN2}{render(payload)}{RESET}")


def print_workflow_success(payload: object) -> None:
    print()
    print(render_workflow_result(payload))


def print_failure(label: str, error: Exception) -> None:
    print(f"{RED}\n❌ {label} failed:{RESET} {error}")


def employee_summary(
    employee_id: int,
    name: str,
    surname: str,
    description: str,
) -> str:
    return f"{employee_id} ({name} {surname}, {description})"


def infer_mode(graphql_url: str) -> str:
    return "docker" if "host.docker.internal" in graphql_url else "bare"


def ensure_runtime(graphql_url: str) -> None:
    runtime_mode = infer_mode(graphql_url)

    if GRAPHQL_LIBRARY_VENV.exists():
        current_prefix = Path(sys.prefix).resolve()
        target_prefix = (GRAPHQL_LIBRARY / ".venv").resolve()
        if current_prefix != target_prefix:
            os.execv(
                str(GRAPHQL_LIBRARY_VENV),
                [str(GRAPHQL_LIBRARY_VENV), __file__, *sys.argv[1:]],
            )

    if not GRAPHQL_LIBRARY_CODE.is_dir():
        fail(
            f"Generated GraphQL library not found. Run 'make library-generate MODE={runtime_mode}' first.",
            color=SOFT_RED,
        )

    sys.path.insert(0, str(GRAPHQL_LIBRARY_CODE))


def render(payload: object) -> str:
    payload = normalize(payload)
    return json.dumps(payload, indent=2, ensure_ascii=False)


def normalize(payload: object) -> object:
    if hasattr(payload, "model_dump"):
        return normalize(payload.model_dump(by_alias=True))
    if isinstance(payload, dict):
        return {key: normalize(value) for key, value in payload.items()}
    if isinstance(payload, list):
        return [normalize(value) for value in payload]
    return payload


def table(headers: list[str], rows: list[list[object]]) -> str:
    string_rows = [[str(cell) for cell in row] for row in rows]
    widths = [len(header) for header in headers]

    for row in string_rows:
        for index, cell in enumerate(row):
            widths[index] = max(widths[index], len(cell))

    def render_row(row: list[str]) -> str:
        return "| " + " | ".join(cell.ljust(widths[index]) for index, cell in enumerate(row)) + " |"

    border = "+-" + "-+-".join("-" * width for width in widths) + "-+"
    lines = [
        colorize(border, GREY),
        colorize(render_row(headers), CYAN),
        colorize(border, GREY),
    ]
    lines.extend(colorize(render_row(row), GREEN2) for row in string_rows)
    lines.append(colorize(border, GREY))
    return "\n".join(lines)


def render_employee_table(employees: list[dict[str, object]]) -> str:
    if not employees:
        return colorize("(no employees)", GREY)

    rows = [
        [
            employee.get("employeeId", ""),
            employee.get("name", ""),
            employee.get("surname", ""),
            employee.get("description", ""),
        ]
        for employee in employees
    ]
    return table(["Employee ID", "Name", "Surname", "Description"], rows)


def render_key_value_table(values: dict[str, object]) -> str:
    rows = [[key, value] for key, value in values.items()]
    return table(["Field", "Value"], rows)


def render_workflow_result(payload: object) -> str:
    data = normalize(payload)

    if isinstance(data, dict):
        if "employee" in data:
            employee = data["employee"]
            if employee is None:
                return colorize("(employee not found)", GREY)
            return render_employee_table([employee])
        if "employees" in data:
            employees = data["employees"]
            if isinstance(employees, list):
                return render_employee_table(employees)
        return render_key_value_table(data)

    return colorize(str(data), GREEN2)


def build_parser() -> argparse.ArgumentParser:
    parser = ColorParser(
        description="Example CLI around the generated FastAPI GraphQL client."
    )
    parser.add_argument(
        "--graphql-url",
        default=DEFAULT_GRAPHQL_URL,
        help="GraphQL endpoint URL.",
    )

    subparsers = parser.add_subparsers(
        dest="command",
        required=True,
        parser_class=ColorParser,
    )

    add_parser = subparsers.add_parser("add-employee")
    add_parser.add_argument("--employee-id", type=int, default=int(time.time()))
    add_parser.add_argument("--employee-name", required=True)
    add_parser.add_argument("--employee-surname", required=True)
    add_parser.add_argument("--employee-description", default="")
    add_parser.set_defaults(handler=add_employee)

    update_parser = subparsers.add_parser("update-employee")
    update_parser.add_argument("--employee-id", type=int, required=True)
    update_parser.add_argument("--employee-name", required=False)
    update_parser.add_argument("--employee-surname", required=False)
    update_parser.add_argument("--employee-description", required=False)
    update_parser.set_defaults(handler=update_employee)

    delete_parser = subparsers.add_parser("delete-employee")
    delete_parser.add_argument("--employee-id", type=int, required=True)
    delete_parser.set_defaults(handler=delete_employee)

    show_parser = subparsers.add_parser("get-employee")
    show_parser.add_argument("--employee-id", type=int, required=True)
    show_parser.set_defaults(handler=get_employee)

    show_all_parser = subparsers.add_parser("get-all-employees")
    show_all_parser.set_defaults(handler=get_all_employees)

    workflow_parser = subparsers.add_parser("workflow")
    workflow_parser.add_argument("--employee-id", type=int, default=int(time.time()))
    workflow_parser.add_argument("--employee-name", default="Max")
    workflow_parser.add_argument("--employee-surname", default="Mustermann")
    workflow_parser.add_argument("--employee-description", default="Developer")
    workflow_parser.add_argument("--updated-employee-name", default="Max")
    workflow_parser.add_argument("--updated-employee-surname", default="Mustermann")
    workflow_parser.add_argument("--updated-employee-description", default="Senior Developer")
    workflow_parser.set_defaults(handler=workflow)

    return parser


def add_employee(args: argparse.Namespace) -> object:
    from fastapi_graphql_client import FastAPIGraphQLClient

    with FastAPIGraphQLClient(url=args.graphql_url) as client:
        return client.mutation_add_employee(
            employee_id=args.employee_id,
            name=args.employee_name,
            surname=args.employee_surname,
            description=args.employee_description,
        )


def update_employee(args: argparse.Namespace) -> object:
    from fastapi_graphql_client import FastAPIGraphQLClient

    with FastAPIGraphQLClient(url=args.graphql_url) as client:
        return client.mutation_update_employee(
            employee_id=args.employee_id,
            name=args.employee_name,
            surname=args.employee_surname,
            description=args.employee_description,
        )


def delete_employee(args: argparse.Namespace) -> object:
    from fastapi_graphql_client import FastAPIGraphQLClient

    with FastAPIGraphQLClient(url=args.graphql_url) as client:
        return client.mutation_delete_employee(employee_id=args.employee_id)


def get_employee(args: argparse.Namespace) -> object:
    from fastapi_graphql_client import FastAPIGraphQLClient

    with FastAPIGraphQLClient(url=args.graphql_url) as client:
        return client.query_employee(args.employee_id)


def get_all_employees(args: argparse.Namespace) -> object:
    from fastapi_graphql_client import FastAPIGraphQLClient

    with FastAPIGraphQLClient(url=args.graphql_url) as client:
        return client.query_employees()


def workflow(args: argparse.Namespace) -> object:
    from fastapi_graphql_client import (
        FastAPIGraphQLClient,
        GraphQLClientGraphQLMultiError,
    )

    print("\n\n" + GREEN + LOGO + RESET)
    print(f"{GREY}endpoint: {args.graphql_url}{RESET}")

    created = False
    with FastAPIGraphQLClient(url=args.graphql_url) as client:
        try:
            try:
                print_step(
                    "Adding employee "
                    + employee_summary(
                        args.employee_id,
                        args.employee_name,
                        args.employee_surname,
                        args.employee_description,
                    )
                    + "..."
                )
                result = client.mutation_add_employee(
                    employee_id=args.employee_id,
                    name=args.employee_name,
                    surname=args.employee_surname,
                    description=args.employee_description,
                )
                created = True
                print_workflow_success(result)
            except GraphQLClientGraphQLMultiError as error:
                print_failure("Add", error)

            try:
                print_step(f"Fetching employee {args.employee_id} after add...")
                result = client.query_employee(args.employee_id)
                print_workflow_success(result)
            except GraphQLClientGraphQLMultiError as error:
                print_failure("Read single after add", error)

            try:
                print_step(
                    "Updating employee "
                    + employee_summary(
                        args.employee_id,
                        args.employee_name,
                        args.employee_surname,
                        args.employee_description,
                    )
                    + " to become "
                    + employee_summary(
                        args.employee_id,
                        args.updated_employee_name,
                        args.updated_employee_surname,
                        args.updated_employee_description,
                    )
                    + "..."
                )
                result = client.mutation_update_employee(
                    employee_id=args.employee_id,
                    name=args.updated_employee_name,
                    surname=args.updated_employee_surname,
                    description=args.updated_employee_description,
                )
                print_workflow_success(result)
            except GraphQLClientGraphQLMultiError as error:
                print_failure("Update", error)

            try:
                print_step(f"Fetching employee {args.employee_id} after update...")
                result = client.query_employee(args.employee_id)
                print_workflow_success(result)
            except GraphQLClientGraphQLMultiError as error:
                print_failure("Read single after update", error)

            try:
                print_step("Fetching all employees...")
                result = client.query_employees()
                print_workflow_success(result)
            except GraphQLClientGraphQLMultiError as error:
                print_failure("Read all", error)
        finally:
            if created:
                try:
                    print_step(
                        "Deleting employee "
                        + employee_summary(
                            args.employee_id,
                            args.updated_employee_name,
                            args.updated_employee_surname,
                            args.updated_employee_description,
                        )
                        + "..."
                    )
                    result = client.mutation_delete_employee(employee_id=args.employee_id)
                    print_workflow_success(result)
                except GraphQLClientGraphQLMultiError as error:
                    print_failure("Delete", error)

    print(f"{GREEN}\n✅ Done.\n{RESET}")
    return None


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    ensure_runtime(args.graphql_url)

    from fastapi_graphql_client import GraphQLClientGraphQLMultiError
    import httpx

    try:
        result = args.handler(args)
    except GraphQLClientGraphQLMultiError as exc:
        fail(f"GraphQL error: {exc}")
    except httpx.ConnectError as exc:
        fail(
            f"Connection error: could not connect to {args.graphql_url}. "
            f"Start the FastAPI service first, for example with 'make up MODE={infer_mode(args.graphql_url)}'."
        )

    if result is not None:
        print(colorize(render(result), GREEN))


if __name__ == "__main__":
    main()
