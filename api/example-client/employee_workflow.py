from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
import time
from typing import Any

import httpx

force_color = os.getenv("FORCE_COLOR", "").strip().lower()
USE_COLOR = (
    os.getenv("NO_COLOR") is None
    and (
        sys.stdout.isatty()
        or force_color in {"1", "true", "yes", "on"}
    )
)
RED = "\033[38;5;196m" if USE_COLOR else ""
GREEN = "\033[38;5;46m" if USE_COLOR else ""
GREEN2 = "\033[32m" if USE_COLOR else ""
BLUE = "\033[38;5;33m" if USE_COLOR else ""
CYAN = "\033[38;5;51m" if USE_COLOR else ""
GREY = "\033[38;5;245m" if USE_COLOR else ""
RESET = "\033[0m" if USE_COLOR else ""

LOGO = r"""
▄▖         ▜     ▄▖  ▗ ▌       ▄▖▜ ▘    ▗
▙▖▚▘▀▌▛▛▌▛▌▐ █▌  ▙▌▌▌▜▘▛▌▛▌▛▌  ▌ ▐ ▌█▌▛▌▜▘
▙▖▞▖█▌▌▌▌▙▌▐▖▙▖  ▌ ▙▌▐▖▌▌▙▌▌▌  ▙▖▐▖▌▙▖▌▌▐▖
         ▌         ▄▌
"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Exercise the generated GraphQL client against the FastAPI endpoint."
    )
    parser.add_argument(
        "--graphql-url",
        default=os.getenv("API_URL", "http://127.0.0.1:8000/graphql"),
        help="GraphQL endpoint URL.",
    )
    parser.add_argument(
        "--employee-id",
        type=int,
        default=int(time.time()),
        help="Employee ID to create for the example workflow.",
    )
    parser.add_argument(
        "--employee-name",
        default="Max",
        help="Employee name used for the add mutation.",
    )
    parser.add_argument(
        "--employee-surname",
        default="Mustermann",
        help="Employee surname used for the add mutation.",
    )
    parser.add_argument(
        "--employee-description",
        default="EG15",
        help="Employee description used for the add mutation.",
    )
    parser.add_argument(
        "--updated-employee-name",
        default="Max",
        help="Employee name used for the update mutation.",
    )
    parser.add_argument(
        "--updated-employee-surname",
        default="Mustermann",
        help="Employee surname used for the update mutation.",
    )
    parser.add_argument(
        "--updated-employee-description",
        default="EG16",
        help="Employee description used for the update mutation.",
    )
    return parser.parse_args()


def print_step(message: str) -> None:
    print(f"\n{CYAN}⭐ {message}{RESET}")


def print_success(payload: Any) -> None:
    print(f"\n{GREEN2}{render_json(payload)}{RESET}")


def print_failure(label: str, error: Exception) -> None:
    print(f"{RED}\n❌ {label} failed:{RESET} {error}")


def render_json(payload: Any) -> str:
    if hasattr(payload, "model_dump"):
        payload = payload.model_dump(by_alias=True)
    return json.dumps(payload, indent=2, ensure_ascii=False)


def employee_summary(
    employee_id: int,
    name: str,
    surname: str,
    description: str,
) -> str:
    return f"{employee_id} ({name} {surname}, {description})"


async def run_workflow(args: argparse.Namespace) -> None:
    from fastapi_graphql_client import (
        FastAPIGraphQLClient,
        GraphQLClientGraphQLMultiError,
    )

    employee = {
        "employee_id": args.employee_id,
        "name": args.employee_name,
        "surname": args.employee_surname,
        "description": args.employee_description,
    }
    updated_employee = {
        "employee_id": args.employee_id,
        "name": args.updated_employee_name,
        "surname": args.updated_employee_surname,
        "description": args.updated_employee_description,
    }

    print("\n\n" + GREEN + LOGO + RESET)
    print(f"{GREY}endpoint: {args.graphql_url}{RESET}")

    async with FastAPIGraphQLClient(url=args.graphql_url) as client:
        created = False
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
                result = await client.mutation_add_employee(**employee)
                created = True
                print_success(result)
            except GraphQLClientGraphQLMultiError as error:
                print_failure("Add", error)

            try:
                print_step(f"Fetching employee {args.employee_id} after add...")
                result = await client.query_employee(args.employee_id)
                print_success(result)
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
                result = await client.mutation_update_employee(**updated_employee)
                print_success(result)
            except GraphQLClientGraphQLMultiError as error:
                print_failure("Update", error)

            try:
                print_step(f"Fetching employee {args.employee_id} after update...")
                result = await client.query_employee(args.employee_id)
                print_success(result)
            except GraphQLClientGraphQLMultiError as error:
                print_failure("Read single after update", error)

            try:
                print_step("Fetching all employees...")
                result = await client.query_employees()
                print_success(result)
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
                    result = await client.mutation_delete_employee(args.employee_id)
                    print_success(result)
                except GraphQLClientGraphQLMultiError as error:
                    print_failure("Delete", error)

    print(f"{GREEN}\n✅ Done.\n{RESET}")


def main() -> None:
    args = parse_args()
    try:
        asyncio.run(run_workflow(args))
    except httpx.ConnectError as exc:
        raise SystemExit(
            f"{RED}Connection error:{RESET} could not connect to {args.graphql_url}. "
            "Start the FastAPI service first, for example with "
            "'make up MODE=docker|bare' from the repository root, or pass "
            "--graphql-url to a running GraphQL endpoint."
        ) from exc


if __name__ == "__main__":
    main()
