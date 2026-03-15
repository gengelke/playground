from __future__ import annotations

from contextlib import asynccontextmanager, contextmanager
from fastapi import FastAPI, HTTPException, Response
from pydantic import BaseModel
import os
import sqlite3
from pathlib import Path
from threading import Lock

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
DATABASE_INIT_LOCK = Lock()
DATABASE_INITIALIZED = False


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
        role TEXT PRIMARY KEY
    )
    """)
    connection.executemany(
        "INSERT OR IGNORE INTO roles (role) VALUES (?)",
        ((role,) for role in DEFAULT_ROLES),
    )


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
            create_roles_table(conn)
            ensure_employees_table(conn)
            result = conn.execute("SELECT COUNT(*) as count FROM employees").fetchone()
            if result["count"] == 0:
                conn.execute("""
                INSERT INTO employees (employee_id, name, surname, role)
                VALUES (?, ?, ?, ?)
                """, (1, "Flash", "Gordon", "Superhero"))
            conn.commit()

        DATABASE_INITIALIZED = True


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
        rows = conn.execute("SELECT role FROM roles ORDER BY rowid").fetchall()
        return [dict(row) for row in rows]


def get_employee_db(employee_id: int):
    with get_connection() as conn:
        row = conn.execute(
            "SELECT * FROM employees WHERE employee_id = ?",
            (employee_id,)
        ).fetchone()
        return dict(row) if row else None


def add_role_db(role: str) -> None:
    with get_connection() as conn:
        conn.execute("INSERT INTO roles (role) VALUES (?)", (role,))
        conn.commit()


def delete_role_db(role: str) -> int:
    with get_connection() as conn:
        cursor = conn.execute("DELETE FROM roles WHERE role = ?", (role,))
        conn.commit()
        return cursor.rowcount


def add_employee_db(employee_id, name, surname, role):
    with get_connection() as conn:
        conn.execute("""
        INSERT INTO employees (employee_id, name, surname, role)
        VALUES (?, ?, ?, ?)
        """, (employee_id, name, surname, role))
        conn.commit()


def update_employee_db(employee_id, name, surname, role) -> int:
    with get_connection() as conn:
        cursor = conn.execute("""
        UPDATE employees
        SET name = ?, surname = ?, role = ?
        WHERE employee_id = ?
        """, (name, surname, role, employee_id))
        conn.commit()
        return cursor.rowcount


def delete_employee_db(employee_id) -> int:
    with get_connection() as conn:
        cursor = conn.execute(
            "DELETE FROM employees WHERE employee_id = ?", (employee_id,)
        )
        conn.commit()
        return cursor.rowcount


# =====================================================
# STARTUP
# =====================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    initialize_database()
    yield


app = FastAPI(lifespan=lifespan)


# =====================================================
# REST API
# =====================================================

class Employee(BaseModel):
    employee_id: int
    name: str
    surname: str
    role: str


# -------- GET all employees --------
@app.get("/employees")
def get_employees():
    return get_employees_db()


@app.get("/roles")
def get_roles():
    return get_roles_db()


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
    return {"message": "Employee added successfully"}


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
    return {"message": "Employee updated successfully"}


# -------- DELETE employee --------
@app.delete("/employees/{employee_id}")
def delete_employee(employee_id: int):
    rows = delete_employee_db(employee_id)
    if rows == 0:
        raise HTTPException(status_code=404, detail="Employee not found")
    return {"message": "Employee deleted successfully"}


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


@strawberry.type
class Mutation:

    @strawberry.mutation
    def add_employee(self, employee_id: int, name: str, surname: str, role: str) -> str:
        try:
            add_employee_db(employee_id, name, surname, role)
        except sqlite3.IntegrityError:
            if get_employee_db(employee_id) is not None:
                raise ValueError(f"Employee {employee_id} already exists")
            raise invalid_role_error(role)
        return "Employee added successfully"

    @strawberry.mutation
    def update_employee(self, employee_id: int, name: str, surname: str, role: str) -> str:
        try:
            rows = update_employee_db(employee_id, name, surname, role)
        except sqlite3.IntegrityError:
            raise invalid_role_error(role)
        if rows == 0:
            raise ValueError(f"Employee {employee_id} not found")
        return "Employee updated successfully"

    @strawberry.mutation
    def delete_employee(self, employee_id: int) -> str:
        if delete_employee_db(employee_id) == 0:
            raise ValueError(f"Employee {employee_id} not found")
        return "Employee deleted successfully"

    @strawberry.mutation
    def add_role(self, role: str) -> str:
        try:
            add_role_db(role)
        except sqlite3.IntegrityError:
            raise ValueError(f"Role '{role}' already exists")
        return "Role added successfully"

    @strawberry.mutation
    def delete_role(self, role: str) -> str:
        try:
            rows = delete_role_db(role)
        except sqlite3.IntegrityError:
            raise role_in_use_error(role)
        if rows == 0:
            raise ValueError(f"Role '{role}' not found")
        return "Role deleted successfully"


schema = strawberry.Schema(query=Query, mutation=Mutation)
graphql_app = GraphQLRouter(schema)

app.include_router(graphql_app, prefix="/graphql")


# Optional: export SDL via curl
@app.get("/schema.graphql")
def export_schema():
    return Response(schema.as_str(), media_type="text/plain")
