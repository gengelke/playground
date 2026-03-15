from __future__ import annotations

import argparse
import importlib.util
import re
import shutil
import subprocess
import sys
from pathlib import Path
from textwrap import indent

from ariadne_codegen.schema import get_graphql_schema_from_url
from graphql import (
    GraphQLEnumType,
    GraphQLField,
    GraphQLInterfaceType,
    GraphQLNonNull,
    GraphQLObjectType,
    GraphQLScalarType,
    GraphQLSchema,
    GraphQLUnionType,
    Undefined,
    build_schema,
    get_named_type,
    print_schema,
)

PACKAGE_NAME = "fastapi_graphql_client"
CLIENT_NAME = "FastAPIGraphQLClient"
WORD_BOUNDARY = re.compile(r"(?<!^)(?=[A-Z])")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a Python GraphQL client library from the FastAPI schema."
    )
    parser.add_argument(
        "--schema-source",
        choices=("local", "remote"),
        default="local",
        help="Load the schema from local FastAPI code or an already running instance.",
    )
    parser.add_argument(
        "--remote-schema-url",
        default="http://127.0.0.1:8000/graphql",
        help="GraphQL endpoint used when --schema-source=remote.",
    )
    parser.add_argument(
        "--fastapi-module-path",
        default=None,
        help="Path to fastapi/main.py used when --schema-source=local.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    workspace_dir = Path(__file__).resolve().parents[1]
    build_dir = workspace_dir / "build"
    schema_path = build_dir / "schema.graphql"
    operations_dir = build_dir / "operations"
    config_path = build_dir / "ariadne-codegen.toml"
    output_dir = workspace_dir / "generated"

    build_dir.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)

    if args.schema_source == "local":
        module_path = (
            Path(args.fastapi_module_path).resolve()
            if args.fastapi_module_path
            else workspace_dir.parent / "fastapi" / "main.py"
        )
        schema, schema_sdl = load_local_schema(module_path)
    else:
        schema = get_graphql_schema_from_url(
            url=args.remote_schema_url,
            headers={},
            verify_ssl=True,
            timeout=30,
        )
        schema_sdl = print_schema(schema)

    schema_path.write_text(schema_sdl + "\n", encoding="utf-8")
    operation_count = generate_operation_documents(schema, operations_dir)
    reset_output_package(output_dir)
    config_path.write_text(
        build_codegen_config(schema_path, operations_dir, output_dir),
        encoding="utf-8",
    )
    run_codegen(config_path, workspace_dir)

    print(
        f"Generated {operation_count} operations into {operations_dir} and refreshed "
        f"{PACKAGE_NAME} in {output_dir} using {args.schema_source} schema source."
    )


def load_local_schema(module_path: Path) -> tuple[GraphQLSchema, str]:
    if not module_path.exists():
        raise FileNotFoundError(f"FastAPI module not found: {module_path}")

    spec = importlib.util.spec_from_file_location("fastapi_codegen_main", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load FastAPI module from {module_path}")

    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)

    schema_object = getattr(module, "schema", None)
    if schema_object is None or not hasattr(schema_object, "as_str"):
        raise RuntimeError(f"Module {module_path} does not expose a Strawberry schema")

    schema_sdl = schema_object.as_str()
    return build_schema(schema_sdl), schema_sdl


def generate_operation_documents(schema: GraphQLSchema, operations_dir: Path) -> int:
    recreate_directory(operations_dir)
    operation_count = 0

    for operation_type, root_type in (
        ("query", schema.query_type),
        ("mutation", schema.mutation_type),
    ):
        if root_type is None:
            continue

        for field_name, field in root_type.fields.items():
            operation_name = f"{root_type.name}{to_pascal_case(field_name)}"
            document = render_operation(operation_type, operation_name, field_name, field)
            file_name = f"{operation_type}_{to_snake_case(field_name)}.graphql"
            (operations_dir / file_name).write_text(document + "\n", encoding="utf-8")
            operation_count += 1

    return operation_count


def render_operation(
    operation_type: str,
    operation_name: str,
    field_name: str,
    field: GraphQLField,
) -> str:
    variable_definitions = ", ".join(
        f"${argument_name}: {argument.type}"
        for argument_name, argument in field.args.items()
    )
    field_arguments = ", ".join(
        f"{argument_name}: ${argument_name}"
        for argument_name in field.args
    )
    selection_set = build_selection_set(field.type, seen_types=())

    header = f"{operation_type} {operation_name}"
    if variable_definitions:
        header = f"{header}({variable_definitions})"

    rendered_field = field_name
    if field_arguments:
        rendered_field = f"{rendered_field}({field_arguments})"
    if selection_set:
        rendered_field = f"{rendered_field} {{\n{indent(selection_set, '    ')}\n  }}"

    return f"{header} {{\n  {rendered_field}\n}}"


def build_selection_set(graphql_type, seen_types: tuple[str, ...]) -> str:
    named_type = get_named_type(graphql_type)

    if isinstance(named_type, (GraphQLScalarType, GraphQLEnumType)):
        return ""

    if isinstance(named_type, GraphQLUnionType):
        selections = ["__typename"]
        for possible_type in named_type.types:
            fragment_body = build_selection_set(
                possible_type,
                seen_types + (named_type.name,),
            )
            if not fragment_body:
                fragment_body = "__typename"
            selections.append(
                f"... on {possible_type.name} {{\n{indent(fragment_body, '  ')}\n}}"
            )
        return "\n".join(selections)

    if isinstance(named_type, (GraphQLObjectType, GraphQLInterfaceType)):
        if named_type.name in seen_types:
            return "__typename"

        selections: list[str] = []
        if isinstance(named_type, GraphQLInterfaceType):
            selections.append("__typename")

        for child_name, child_field in named_type.fields.items():
            if has_required_arguments(child_field):
                continue
            child_selection = build_selection_set(
                child_field.type,
                seen_types + (named_type.name,),
            )
            if child_selection:
                selections.append(
                    f"{child_name} {{\n{indent(child_selection, '  ')}\n}}"
                )
            else:
                selections.append(child_name)

        return "\n".join(selections or ["__typename"])

    return ""


def has_required_arguments(field: GraphQLField) -> bool:
    for argument in field.args.values():
        if (
            isinstance(argument.type, GraphQLNonNull)
            and argument.default_value is Undefined
        ):
            return True
    return False


def build_codegen_config(schema_path: Path, operations_dir: Path, output_dir: Path) -> str:
    return "\n".join(
        (
            "[tool.ariadne-codegen]",
            f'schema_path = "{schema_path.as_posix()}"',
            f'queries_path = "{operations_dir.as_posix()}"',
            f'target_package_name = "{PACKAGE_NAME}"',
            f'target_package_path = "{output_dir.as_posix()}"',
            f'client_name = "{CLIENT_NAME}"',
            'include_comments = "stable"',
            "convert_to_snake_case = true",
            "async_client = false",
        )
    )


def run_codegen(config_path: Path, workspace_dir: Path) -> None:
    subprocess.run(
        [sys.executable, "-m", "ariadne_codegen", "--config", str(config_path)],
        cwd=workspace_dir,
        check=True,
    )


def reset_output_package(output_dir: Path) -> None:
    package_dir = output_dir / PACKAGE_NAME
    if package_dir.exists():
        shutil.rmtree(package_dir)


def recreate_directory(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def to_pascal_case(value: str) -> str:
    words = WORD_BOUNDARY.sub(" ", value).replace("-", " ").replace("_", " ").split()
    return "".join(word[:1].upper() + word[1:] for word in words)


def to_snake_case(value: str) -> str:
    return WORD_BOUNDARY.sub("_", value).replace("-", "_").lower()


if __name__ == "__main__":
    main()
