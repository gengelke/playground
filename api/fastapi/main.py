from __future__ import annotations

import base64
import binascii
import logging
import os
import secrets
import sqlite3
from contextlib import asynccontextmanager, contextmanager
from logging.handlers import RotatingFileHandler
from pathlib import Path
from threading import Lock
from time import perf_counter

from fastapi import FastAPI, HTTPException, Request, Response
from pydantic import BaseModel
import strawberry
from strawberry.fastapi import GraphQLRouter


# Prefer mounted Docker path if available; otherwise keep the sqlite file in fastapi/.
APP_DIR = Path(__file__).resolve().parent
DEFAULT_ROLES = ("Developer", "Senior Developer", "Superhero", "AvD")
default_db_path = Path("/data/company.sqlite") if Path("/data").exists() else APP_DIR / "company.sqlite"
database_path = Path(os.getenv("DATABASE_PATH", str(default_db_path)))
if not database_path.is_absolute():
    database_path = APP_DIR / database_path
DATABASE = str(database_path)
default_log_path = Path("/data/fastapi.log") if Path("/data").exists() else APP_DIR / "runtime" / "fastapi.log"
log_path = Path(os.getenv("FASTAPI_LOG_PATH", str(default_log_path)))
if not log_path.is_absolute():
    log_path = APP_DIR / log_path
LOG_PATH = log_path
LOG_LEVEL = getattr(logging, os.getenv("FASTAPI_LOG_LEVEL", "INFO").upper(), logging.INFO)
LOG_FORMAT = "%(asctime)s %(levelname)s [%(name)s] %(message)s"
DATABASE_INIT_LOCK = Lock()
DATABASE_INITIALIZED = False
FASTAPI_BASIC_AUTH_USERNAME = os.getenv("FASTAPI_BASIC_AUTH_USERNAME", "admin")
FASTAPI_BASIC_AUTH_PASSWORD = os.getenv("FASTAPI_BASIC_AUTH_PASSWORD", "password")
PUBLIC_PATHS = frozenset({"/healthz"})


# =====================================================
# LOGGING
# =====================================================

def configure_logging() -> logging.Logger:
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)

    formatter = logging.Formatter(LOG_FORMAT)
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)
    file_handler = RotatingFileHandler(LOG_PATH, maxBytes=1_000_000, backupCount=3)
    file_handler.setFormatter(formatter)

    root_logger = logging.getLogger()
    for handler in list(root_logger.handlers):
        root_logger.removeHandler(handler)
        handler.close()
    root_logger.setLevel(LOG_LEVEL)
    root_logger.addHandler(console_handler)
    root_logger.addHandler(file_handler)

    for logger_name in ("uvicorn", "uvicorn.error", "strawberry"):
        configured_logger = logging.getLogger(logger_name)
        for handler in list(configured_logger.handlers):
            configured_logger.removeHandler(handler)
            handler.close()
        configured_logger.setLevel(LOG_LEVEL)
        configured_logger.propagate = True

    access_logger = logging.getLogger("uvicorn.access")
    for handler in list(access_logger.handlers):
        access_logger.removeHandler(handler)
        handler.close()
    access_logger.disabled = True

    return logging.getLogger("playground.fastapi")


LOGGER = configure_logging()


def path_is_public(path: str) -> bool:
    return path in PUBLIC_PATHS


def unauthorized_response() -> Response:
    return Response(
        status_code=401,
        headers={"WWW-Authenticate": 'Basic realm="FastAPI"'},
    )


def request_has_valid_basic_auth(request: Request) -> bool:
    authorization = request.headers.get("Authorization", "")
    scheme, _, encoded_credentials = authorization.partition(" ")
    if scheme.lower() != "basic" or not encoded_credentials:
        return False

    try:
        decoded = base64.b64decode(encoded_credentials, validate=True).decode("utf-8")
    except (ValueError, UnicodeDecodeError, binascii.Error):
        return False

    username, separator, password = decoded.partition(":")
    if not separator:
        return False

    return (
        secrets.compare_digest(username, FASTAPI_BASIC_AUTH_USERNAME)
        and secrets.compare_digest(password, FASTAPI_BASIC_AUTH_PASSWORD)
    )


# =====================================================
# DATABASE LAYER (CENTRALIZED)
# =====================================================

def open_connection():
    Path(DATABASE).parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(DATABASE)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    return connection


def table_exists(connection: sqlite3.Connection, table_name: str) -> bool:
    row = connection.execute(
        """
        SELECT 1
        FROM sqlite_master
        WHERE type = 'table' AND name = ?
        """,
        (table_name,),
    ).fetchone()
    return row is not None


def get_table_columns(connection: sqlite3.Connection, table_name: str) -> set[str]:
    rows = connection.execute(f'PRAGMA table_info("{table_name}")').fetchall()
    return {row["name"] for row in rows}


def has_roles_foreign_key(connection: sqlite3.Connection) -> bool:
    rows = connection.execute('PRAGMA foreign_key_list("employees")').fetchall()
    return any(row["table"] == "roles" and row["from"] == "role" for row in rows)


def create_roles_table(connection: sqlite3.Connection) -> None:
    connection.execute("""
    CREATE TABLE IF NOT EXISTS roles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        role TEXT UNIQUE NOT NULL
    )
    """)
    connection.executemany(
        "INSERT OR IGNORE INTO roles (role) VALUES (?)",
        ((role,) for role in DEFAULT_ROLES),
    )


def migrate_roles_table(connection: sqlite3.Connection) -> None:
    rows = connection.execute("SELECT role FROM roles ORDER BY rowid").fetchall()
    connection.execute("ALTER TABLE roles RENAME TO roles_legacy")
    create_roles_table(connection)
    connection.executemany(
        "INSERT OR IGNORE INTO roles (role) VALUES (?)",
        ((row["role"],) for row in rows),
    )
    connection.execute("DROP TABLE roles_legacy")


def ensure_roles_table(connection: sqlite3.Connection) -> None:
    if not table_exists(connection, "roles"):
        create_roles_table(connection)
        return
    if "id" not in get_table_columns(connection, "roles"):
        migrate_roles_table(connection)


def create_employees_table(connection: sqlite3.Connection) -> None:
    connection.execute("""
    CREATE TABLE employees (
        employee_id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        surname TEXT NOT NULL,
        role TEXT NOT NULL REFERENCES roles(role)
    )
    """)


def migrate_employees_table(connection: sqlite3.Connection, role_column: str) -> None:
    rows = connection.execute(
        f"""
        SELECT employee_id, name, surname, {role_column} AS role
        FROM employees
        """
    ).fetchall()

    for row in rows:
        role = row["role"] or DEFAULT_ROLES[0]
        connection.execute(
            "INSERT OR IGNORE INTO roles (role) VALUES (?)",
            (role,),
        )

    connection.execute("ALTER TABLE employees RENAME TO employees_legacy")
    create_employees_table(connection)
    connection.executemany(
        """
        INSERT INTO employees (employee_id, name, surname, role)
        VALUES (?, ?, ?, ?)
        """,
        (
            (
                row["employee_id"],
                row["name"],
                row["surname"],
                row["role"] or DEFAULT_ROLES[0],
            )
            for row in rows
        ),
    )
    connection.execute("DROP TABLE employees_legacy")


def ensure_employees_table(connection: sqlite3.Connection) -> None:
    if not table_exists(connection, "employees"):
        create_employees_table(connection)
        return

    columns = get_table_columns(connection, "employees")
    if "role" in columns and "description" not in columns and has_roles_foreign_key(connection):
        return

    role_column = "role" if "role" in columns else "description"
    migrate_employees_table(connection, role_column)


def invalid_role_error(role: str) -> ValueError:
    valid_roles = ", ".join(item["role"] for item in get_roles_db())
    return ValueError(f"Role '{role}' does not exist. Known roles: {valid_roles}")


def role_in_use_error(role: str) -> ValueError:
    return ValueError(f"Role '{role}' is still assigned to one or more employees")


def initialize_database() -> None:
    global DATABASE_INITIALIZED
    if DATABASE_INITIALIZED:
        return

    with DATABASE_INIT_LOCK:
        if DATABASE_INITIALIZED:
            return

        with open_connection() as conn:
            ensure_roles_table(conn)
            ensure_employees_table(conn)
            result = conn.execute("SELECT COUNT(*) as count FROM employees").fetchone()
            if result["count"] == 0:
                conn.execute("""
                INSERT INTO employees (employee_id, name, surname, role)
                VALUES (?, ?, ?, ?)
                """, (1, "Flash", "Gordon", "Superhero"))
            conn.commit()

        DATABASE_INITIALIZED = True
        LOGGER.info("Initialized database at %s", DATABASE)


@contextmanager
def get_connection():
    initialize_database()
    connection = open_connection()
    try:
        yield connection
    finally:
        connection.close()


def get_employees_db():
    with get_connection() as conn:
        rows = conn.execute("SELECT * FROM employees").fetchall()
        return [dict(row) for row in rows]


def get_roles_db():
    with get_connection() as conn:
        rows = conn.execute("SELECT id, role FROM roles ORDER BY id").fetchall()
        return [dict(row) for row in rows]


def get_employee_db(employee_id: int):
    with get_connection() as conn:
        row = conn.execute(
            "SELECT * FROM employees WHERE employee_id = ?",
            (employee_id,)
        ).fetchone()
        return dict(row) if row else None


def add_role_db(role: str) -> int:
    with get_connection() as conn:
        cursor = conn.execute("INSERT INTO roles (role) VALUES (?)", (role,))
        conn.commit()
        LOGGER.info("Added role '%s'", role)
        return cursor.lastrowid


def get_role_by_id_db(role_id: int) -> dict | None:
    with get_connection() as conn:
        row = conn.execute("SELECT id, role FROM roles WHERE id = ?", (role_id,)).fetchone()
        return dict(row) if row else None


def delete_role_by_id_db(role_id: int) -> dict | None:
    with get_connection() as conn:
        row = conn.execute("SELECT id, role FROM roles WHERE id = ?", (role_id,)).fetchone()
        if row is None:
            return None
        conn.execute("DELETE FROM roles WHERE id = ?", (role_id,))
        conn.commit()
        LOGGER.info("Deleted role id=%s ('%s')", role_id, row["role"])
        return dict(row)


def delete_role_db(role: str) -> dict | None:
    with get_connection() as conn:
        row = conn.execute("SELECT id, role FROM roles WHERE role = ?", (role,)).fetchone()
        if row is None:
            return None
        conn.execute("DELETE FROM roles WHERE role = ?", (role,))
        conn.commit()
        LOGGER.info("Deleted role '%s'", role)
        return dict(row)


def add_employee_db(employee_id, name, surname, role):
    with get_connection() as conn:
        conn.execute("""
        INSERT INTO employees (employee_id, name, surname, role)
        VALUES (?, ?, ?, ?)
        """, (employee_id, name, surname, role))
        conn.commit()
    LOGGER.info("Added employee %s", employee_id)


def update_employee_db(employee_id, name, surname, role) -> int:
    with get_connection() as conn:
        cursor = conn.execute("""
        UPDATE employees
        SET name = ?, surname = ?, role = ?
        WHERE employee_id = ?
        """, (name, surname, role, employee_id))
        conn.commit()
        if cursor.rowcount:
            LOGGER.info("Updated employee %s", employee_id)
        return cursor.rowcount


def delete_employee_db(employee_id) -> int:
    with get_connection() as conn:
        cursor = conn.execute(
            "DELETE FROM employees WHERE employee_id = ?", (employee_id,)
        )
        conn.commit()
        if cursor.rowcount:
            LOGGER.info("Deleted employee %s", employee_id)
        return cursor.rowcount


# =====================================================
# STARTUP
# =====================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    initialize_database()
    LOGGER.info("FastAPI startup complete (database=%s, log_file=%s)", DATABASE, LOG_PATH)
    yield
    LOGGER.info("FastAPI shutdown complete")


app = FastAPI(lifespan=lifespan)


@app.middleware("http")
async def log_requests(request: Request, call_next):
    started_at = perf_counter()
    try:
        if path_is_public(request.url.path) or request_has_valid_basic_auth(request):
            response = await call_next(request)
        else:
            response = unauthorized_response()
    except Exception:
        duration_ms = (perf_counter() - started_at) * 1000
        LOGGER.exception(
            "Request failed: %s %s (%.2f ms)",
            request.method,
            request.url.path,
            duration_ms,
        )
        raise

    duration_ms = (perf_counter() - started_at) * 1000
    LOGGER.info(
        "%s %s -> %s (%.2f ms)",
        request.method,
        request.url.path,
        response.status_code,
        duration_ms,
    )
    return response


# =====================================================
# REST API
# =====================================================

class Employee(BaseModel):
    employee_id: int
    name: str
    surname: str
    role: str


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


# -------- GET all employees --------
@app.get("/employees")
def get_employees():
    return get_employees_db()


@app.get("/roles")
def get_roles():
    return get_roles_db()


class Role(BaseModel):
    role: str


@app.post("/roles", status_code=201)
def add_role(role: Role):
    try:
        role_id = add_role_db(role.role)
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=409, detail=f"Role '{role.role}' already exists")
    return {"id": role_id, "role": role.role}


# -------- GET single employee --------
@app.get("/employees/{employee_id}")
def get_employee(employee_id: int):
    employee = get_employee_db(employee_id)
    if not employee:
        raise HTTPException(status_code=404, detail="Employee not found")
    return employee


# -------- POST add employee --------
@app.post("/employees")
def add_employee(employee: Employee):
    try:
        add_employee_db(
            employee.employee_id,
            employee.name,
            employee.surname,
            employee.role
        )
    except sqlite3.IntegrityError:
        employee_exists = get_employee_db(employee.employee_id) is not None
        if employee_exists:
            raise HTTPException(status_code=409, detail="Employee with this ID already exists")
        raise HTTPException(
            status_code=400,
            detail=str(invalid_role_error(employee.role)),
        )
    return employee


# -------- PUT update employee --------
@app.put("/employees/{employee_id}")
def update_employee(employee_id: int, employee: Employee):
    if employee.employee_id != employee_id:
        raise HTTPException(
            status_code=400,
            detail="employee_id in path and body must match",
        )
    try:
        rows = update_employee_db(
            employee_id,
            employee.name,
            employee.surname,
            employee.role
        )
    except sqlite3.IntegrityError:
        raise HTTPException(
            status_code=400,
            detail=str(invalid_role_error(employee.role)),
        )
    if rows == 0 and get_employee_db(employee_id) is None:
        raise HTTPException(status_code=404, detail="Employee not found")
    if rows == 0:
        raise HTTPException(
            status_code=400,
            detail=str(invalid_role_error(employee.role)),
        )
    return employee


# -------- DELETE employee --------
@app.delete("/employees/{employee_id}")
def delete_employee(employee_id: int):
    employee = get_employee_db(employee_id)
    if employee is None:
        raise HTTPException(status_code=404, detail="Employee not found")
    delete_employee_db(employee_id)
    return employee


# -------- GET single role by id --------
@app.get("/roles/{role_id}")
def get_role_by_id(role_id: int):
    role = get_role_by_id_db(role_id)
    if role is None:
        raise HTTPException(status_code=404, detail=f"Role with id {role_id} not found")
    return role


# -------- DELETE role by id --------
@app.delete("/roles/by-id/{role_id}")
def delete_role_by_id(role_id: int):
    try:
        deleted = delete_role_by_id_db(role_id)
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=409, detail="Role is still assigned to one or more employees")
    if deleted is None:
        raise HTTPException(status_code=404, detail=f"Role with id {role_id} not found")
    return deleted


# -------- DELETE role by name --------
@app.delete("/roles/{role}")
def delete_role(role: str):
    try:
        deleted = delete_role_db(role)
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=409, detail=str(role_in_use_error(role)))
    if deleted is None:
        raise HTTPException(status_code=404, detail=f"Role '{role}' not found")
    return deleted


# =====================================================
# GRAPHQL
# =====================================================

@strawberry.type
class EmployeeType:
    employee_id: int
    name: str
    surname: str
    role: str


@strawberry.type
class RoleType:
    id: int
    role: str


@strawberry.type
class Query:

    @strawberry.field
    def employees(self) -> list[EmployeeType]:
        employees = get_employees_db()
        return [EmployeeType(**emp) for emp in employees]

    @strawberry.field
    def roles(self) -> list[RoleType]:
        roles = get_roles_db()
        return [RoleType(**role) for role in roles]

    @strawberry.field
    def employee(self, employee_id: int) -> EmployeeType | None:
        employee = get_employee_db(employee_id)
        if employee:
            return EmployeeType(**employee)
        return None

    @strawberry.field
    def role(self, id: int) -> RoleType | None:
        r = get_role_by_id_db(id)
        return RoleType(**r) if r else None


@strawberry.type
class Mutation:

    @strawberry.mutation
    def add_employee(self, employee_id: int, name: str, surname: str, role: str) -> EmployeeType:
        try:
            add_employee_db(employee_id, name, surname, role)
        except sqlite3.IntegrityError:
            if get_employee_db(employee_id) is not None:
                raise ValueError(f"Employee {employee_id} already exists")
            raise invalid_role_error(role)
        return EmployeeType(employee_id=employee_id, name=name, surname=surname, role=role)

    @strawberry.mutation
    def update_employee(self, employee_id: int, name: str, surname: str, role: str) -> EmployeeType:
        try:
            rows = update_employee_db(employee_id, name, surname, role)
        except sqlite3.IntegrityError:
            raise invalid_role_error(role)
        if rows == 0:
            raise ValueError(f"Employee {employee_id} not found")
        return EmployeeType(employee_id=employee_id, name=name, surname=surname, role=role)

    @strawberry.mutation
    def delete_employee(self, employee_id: int) -> EmployeeType:
        employee = get_employee_db(employee_id)
        if employee is None:
            raise ValueError(f"Employee {employee_id} not found")
        delete_employee_db(employee_id)
        return EmployeeType(**employee)

    @strawberry.mutation
    def add_role(self, role: str) -> RoleType:
        try:
            role_id = add_role_db(role)
        except sqlite3.IntegrityError:
            raise ValueError(f"Role '{role}' already exists")
        return RoleType(id=role_id, role=role)

    @strawberry.mutation
    def delete_role(self, role: str) -> RoleType:
        try:
            deleted = delete_role_db(role)
        except sqlite3.IntegrityError:
            raise role_in_use_error(role)
        if deleted is None:
            raise ValueError(f"Role '{role}' not found")
        return RoleType(**deleted)

    @strawberry.mutation
    def delete_role_by_id(self, id: int) -> RoleType:
        try:
            deleted = delete_role_by_id_db(id)
        except sqlite3.IntegrityError:
            raise ValueError(f"Role with id {id} is still assigned to one or more employees")
        if deleted is None:
            raise ValueError(f"Role with id {id} not found")
        return RoleType(**deleted)


schema = strawberry.Schema(query=Query, mutation=Mutation)
graphql_app = GraphQLRouter(schema)

app.include_router(graphql_app, prefix="/graphql")


# Optional: export SDL via curl
@app.get("/schema.graphql")
def export_schema():
    return Response(schema.as_str(), media_type="text/plain")
