import os
import pytest
import random

from generated_client.client import Client
from generated_client.exceptions import GraphQLClientGraphQLMultiError

API_URL = os.getenv("API_URL", "http://127.0.0.1:8000/graphql")


@pytest.mark.asyncio
async def test_get_employees():
    client = Client(url=API_URL)
    result = await client.get_employees()
    payload = result.model_dump()
    assert "employees" in payload
    assert isinstance(payload["employees"], list)


@pytest.mark.asyncio
async def test_employee_mutation_flow():
    client = Client(url=API_URL)
    employee_id = random.randint(10000, 20000)

    add_result = await client.add_employee(
        employee_id=employee_id,
        name="Test",
        surname="User",
        description="Test employee",
    )
    assert add_result.model_dump()["add_employee"] == "Employee added successfully"

    try:
        update_result = await client.update_employee(
            employee_id=employee_id,
            name="Test",
            surname="User",
            description="Updated test employee",
        )
        assert update_result.model_dump()["update_employee"] == "Employee updated successfully"

        delete_result = await client.delete_employee(employee_id=employee_id)
        assert delete_result.model_dump()["delete_employee"] == "Employee deleted successfully"

        with pytest.raises(GraphQLClientGraphQLMultiError):
            await client.delete_employee(employee_id=employee_id)
    except Exception:
        await client.delete_employee(employee_id=employee_id)
        raise
