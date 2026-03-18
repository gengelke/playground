# API Playground

> [!WARNING]
> This repository is an experimental setup for educational purposes only.
> Do not expose any part of it to the public internet.
> It uses insecure defaults such as default passwords and other convenience settings that are only acceptable for isolated local testing.

This directory contains three related pieces:

- `fastapi/`: the REST + GraphQL service
- `graphql-library/`: generated Python package for the GraphQL client
- `example-client/`: end-to-end workflow client that exercises the generated package

## Main Commands

Start or stop the FastAPI service:

```bash
make up MODE=docker
make up MODE=bare
make down MODE=docker
make down MODE=bare
```

Generate the GraphQL client library:

```bash
make library-generate MODE=docker
make library-generate MODE=bare
```

- `MODE=docker` builds and runs the generator in Docker and uses the remote schema.
- `MODE=bare` uses the local Python virtualenv and defaults to the local schema.

Run the end-to-end example client:

```bash
make run MODE=docker
make run MODE=bare
```

- `MODE=docker` runs the example client in a container.
- `MODE=bare` runs it locally and will regenerate the bare-mode library environment if it is missing.

Useful FastAPI endpoints:

- `GET /employees`: list all employees
- `GET /employees/{employee_id}`: fetch one employee
- `POST /employees`, `PUT /employees/{employee_id}`, `DELETE /employees/{employee_id}`: mutate employee data
- `GET /roles`: list all roles
- `GET /roles/{role_id}`: fetch one role by numeric ID
- `POST /roles`: add a new role
- `DELETE /roles/{role}`: delete a role by name
- `DELETE /roles/by-id/{role_id}`: delete a role by numeric ID
- GraphQL exposes the same employee operations plus `roles`, `role(id)`, `addRole`, `deleteRole`, and `deleteRoleById`

Run the example client CLI directly from `api/`:

```bash
./example-client/company.py employee add --employee-name Erika --employee-surname Mustermann --employee-role Developer
./example-client/company.py employee update --employee-id 4711 --employee-name Erika --employee-surname Mustermann --employee-role "Senior Developer"
./example-client/company.py employee delete --employee-id 4711
./example-client/company.py employee get --employee-id 4711
./example-client/company.py employee list
./example-client/company.py role add --role Architect
./example-client/company.py role get --role Architect
./example-client/company.py role get --id 5
./example-client/company.py role delete --role Architect
./example-client/company.py role delete --id 5
./example-client/company.py role list
./example-client/company.py workflow --employee-name Erika --employee-surname Mustermann --employee-role Developer
```

Single commands print JSON results. The `workflow` command prints step-by-step tables.

## Generated Artifacts

The API area generates local state in these locations:

- `fastapi/.venv/`
- `fastapi/data/`
- `fastapi/runtime/`
- `fastapi/company.sqlite`
- `graphql-library/.venv/`
- `graphql-library/build/`
- `graphql-library/generated/`
- `graphql-library/dist/`
- `graphql-library/*.egg-info/`
- Python bytecode under `example-client/`, `fastapi/`, and `graphql-library/`

These paths are covered by the repository `.gitignore` files.

## Cleanup

Remove generated API artifacts:

```bash
make distclean
```

This delegates to:

- `fastapi/distclean`: removes runtime state, local DB, Docker data, and venv
- `graphql-library/distclean`: removes build output, generated package, dist output, egg-info, and venv
- `example-client/distclean`: removes Python cache artifacts
