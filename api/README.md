## Playground for REST and GraphQL APIs

This project provides a FastAPI service on `127.0.0.1:8000` with:
- REST endpoints (`/employees`, `/employees/{employee_id}`)
- GraphQL endpoint (`/graphql`)
- GraphQL SDL export endpoint (`/schema.graphql`)

The GraphQL schema is used to generate a Python client (`generated_client`), and tests run against that generated client.
You can run everything locally (venv + bash) or with Docker.

## Quick Start
```bash
# full local workflow: start API, codegen, install, test, run example
make
```

```bash
make clean
make distclean
```

### Start API without Docker
```bash
make install
make run
```

Background mode:
```bash
make run-bg
make stop
```

To regenerate the GraphQL client from Bash:
```bash
make codegen
```

Run tests and the example client:
```bash
make test
make example
make cli-list
```

### Start API with Docker
```bash
make run-docker
```

Regenerate GraphQL client inside Docker:
```bash
make codegen-docker
```

Stop Docker services:
```bash
make stop-docker
```

### Optional one-shot workflows:
```bash
make all-local
make all-docker
```

### Open
```
http://127.0.0.1:8000/docs
http://127.0.0.1:8000/graphql
```

### REST - GET all employees
```
curl http://127.0.0.1:8000/employees
```

### REST - POST add employee
```
curl -X POST http://127.0.0.1:8000/employees \
  -H "Content-Type: application/json" \
  -d '{
    "employee_id": 2,
    "name": "Alice",
    "surname": "Smith",
    "description": "Project Manager"
  }'
```

### REST - PUT update employee
```bash
# note: employee_id in path and request body must match
curl -X PUT http://127.0.0.1:8000/employees/2 \
  -H "Content-Type: application/json" \
  -d '{
    "employee_id": 2,
    "name": "Alice",
    "surname": "Smith",
    "description": "Senior Project Manager"
  }'

```

### REST - DELETE employee
```
curl -X DELETE http://127.0.0.1:8000/employees/2
```

### GraphQL Query - Read employees
```
curl -X POST http://127.0.0.1:8000/graphql \
  -H "Content-Type: application/json" \
  -d '{
    "query": "query { employees { employeeId name surname description } }"
  }'
```

### GraphQL Mutation — Add Employee
```
curl -X POST http://127.0.0.1:8000/graphql \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation { addEmployee(employeeId: 3, name: \"Bob\", surname: \"Brown\", description: \"Developer\") }"
  }'
```

### GraphQL Mutation — Update Employee
```
curl -X POST http://127.0.0.1:8000/graphql \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation { updateEmployee(employeeId: 3, name: \"Bob\", surname: \"Brown\", description: \"Senior Developer\") }"
  }'
```

### GraphQL Mutation — Delete Employee
```
curl -X POST http://127.0.0.1:8000/graphql \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation { deleteEmployee(employeeId: 3) }"
  }'
```

### Use the Python library in a script
```bash
rm -rf .venv/
python3 -m venv .venv
source .venv/bin/activate

unset SSL_CERT_FILE
unset REQUESTS_CA_BUNDLE
unset CURL_CA_BUNDLE

pip3 install -U pip
pip3 install pydantic httpx

python3 example_client.py
```

### Install and use the Python library directly in CLI
```bash
pip install -e .
employee-cli list
```

### Vibe coding prompts
```
i am a python rookie. generate simple plain easy to understand code which uses
an sqlite database named company.sqlite. the database includes a table named
employees. each entry consists of string 'name', string 'surname', string
'description', integer 'employee_id'.
```
```
code looks great. pleas add simple plain easy to understand fastapi code which
adds and entry to the employee table when REST API endpoint /employee is called
with POST. it returns all existing entries of table employee when /employee is
called with GET. The entry gets deleted when endpoint is called with DELETE.
Needs a function to update existing entries as well.
```
```
code looks great. pleas add simple plain easy to understand fastapi code which
adds graphql functionality in addition to the existing REST stuff
```
```
code looks great. but an update operation is missing in the graphql. 
please show the complete code
```
```
code looks great. use a more flexible approach in Query (Read) instead of rows)
please show the complete code
```
```
code looks great. can we pull the database connect parts into a centrailized
location so i would have to change it only once in case i wanted to use another
database like postgres in future instead of sqlite?
```
```
the code looks great. please add an initial entry to the employee table during
statup of the app
```
