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
default_db_path = Path("/data/company.sqlite") if Path("/data").exists() else Path(__file__).resolve().parent / "company.sqlite"
DATABASE = os.getenv("DATABASE_PATH", str(default_db_path))
DATABASE_INIT_LOCK = Lock()
DATABASE_INITIALIZED = False


# =====================================================
# DATABASE LAYER (CENTRALIZED)
# =====================================================

def open_connection():
    connection = sqlite3.connect(DATABASE)
    connection.row_factory = sqlite3.Row
    return connection


def initialize_database() -> None:
    global DATABASE_INITIALIZED
    if DATABASE_INITIALIZED:
        return

    with DATABASE_INIT_LOCK:
        if DATABASE_INITIALIZED:
            return

        with open_connection() as conn:
            conn.execute("""
            CREATE TABLE IF NOT EXISTS employees (
                employee_id INTEGER PRIMARY KEY,
                name TEXT,
                surname TEXT,
                description TEXT
            )
            """)
            result = conn.execute("SELECT COUNT(*) as count FROM employees").fetchone()
            if result["count"] == 0:
                conn.execute("""
                INSERT INTO employees (employee_id, name, surname, description)
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


def get_employee_db(employee_id: int):
    with get_connection() as conn:
        row = conn.execute(
            "SELECT * FROM employees WHERE employee_id = ?",
            (employee_id,)
        ).fetchone()
        return dict(row) if row else None


def add_employee_db(employee_id, name, surname, description):
    with get_connection() as conn:
        conn.execute("""
        INSERT INTO employees (employee_id, name, surname, description)
        VALUES (?, ?, ?, ?)
        """, (employee_id, name, surname, description))
        conn.commit()


def update_employee_db(employee_id, name, surname, description) -> int:
    with get_connection() as conn:
        cursor = conn.execute("""
        UPDATE employees
        SET name = ?, surname = ?, description = ?
        WHERE employee_id = ?
        """, (name, surname, description, employee_id))
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
    description: str


# -------- GET all employees --------
@app.get("/employees")
def get_employees():
    return get_employees_db()


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
            employee.description
        )
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=409, detail="Employee with this ID already exists")
    return {"message": "Employee added successfully"}


# -------- PUT update employee --------
@app.put("/employees/{employee_id}")
def update_employee(employee_id: int, employee: Employee):
    if employee.employee_id != employee_id:
        raise HTTPException(
            status_code=400,
            detail="employee_id in path and body must match",
        )
    rows = update_employee_db(
        employee_id,
        employee.name,
        employee.surname,
        employee.description
    )
    if rows == 0:
        raise HTTPException(status_code=404, detail="Employee not found")
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
    description: str


@strawberry.type
class Query:

    @strawberry.field
    def employees(self) -> list[EmployeeType]:
        employees = get_employees_db()
        return [EmployeeType(**emp) for emp in employees]

    @strawberry.field
    def employee(self, employee_id: int) -> EmployeeType | None:
        employee = get_employee_db(employee_id)
        if employee:
            return EmployeeType(**employee)
        return None


@strawberry.type
class Mutation:

    @strawberry.mutation
    def add_employee(self, employee_id: int, name: str, surname: str, description: str) -> str:
        try:
            add_employee_db(employee_id, name, surname, description)
        except sqlite3.IntegrityError:
            raise ValueError(f"Employee {employee_id} already exists")
        return "Employee added successfully"

    @strawberry.mutation
    def update_employee(self, employee_id: int, name: str, surname: str, description: str) -> str:
        if update_employee_db(employee_id, name, surname, description) == 0:
            raise ValueError(f"Employee {employee_id} not found")
        return "Employee updated successfully"

    @strawberry.mutation
    def delete_employee(self, employee_id: int) -> str:
        if delete_employee_db(employee_id) == 0:
            raise ValueError(f"Employee {employee_id} not found")
        return "Employee deleted successfully"


schema = strawberry.Schema(query=Query, mutation=Mutation)
graphql_app = GraphQLRouter(schema)

app.include_router(graphql_app, prefix="/graphql")


# Optional: export SDL via curl
@app.get("/schema.graphql")
def export_schema():
    return Response(schema.as_str(), media_type="text/plain")
