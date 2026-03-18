# Local Gitea + 2 Runners (Docker or Bare)

> [!WARNING]
> This repository is an experimental setup for educational purposes only.
> Do not expose any part of it to the public internet.
> It uses insecure defaults such as default passwords and other convenience settings that are only acceptable for isolated local testing.

This setup runs one local Gitea instance and attaches two action runners.
All first-run initialization is automatic.

## Modes

- `MODE=docker`: runs Gitea and both runners in Docker.
- `MODE=bare`: runs Gitea and both runners as local processes (no Docker).

## Quick start

```bash
make up MODE=docker
# or
make up MODE=bare
```

After startup, login credentials are printed to the CLI when they are auto-managed.

Stop:

```bash
make down MODE=docker
# or
make down MODE=bare
```

Logs:

```bash
make logs MODE=docker
# or
make logs MODE=bare
```

## Defaults you can override

```bash
GITEA_HTTP_PORT=3000
GITEA_SSH_PORT=2222
GITEA_ROOT_URL=http://localhost:3000/
GITEA_ADMIN_USER=admin
GITEA_ADMIN_PASSWORD=password
GITEA_ADMIN_EMAIL=admin@example.com
GITEA_USER=myuser
GITEA_USER_PASSWORD=password
GITEA_USER_EMAIL=myuser@example.com
GITEA_AUTO_ADD_EXAMPLE_PIPELINE_WORKFLOW=true
GITEA_REMOVE_EXAMPLE_WORKFLOW_REPO=false
GITEA_AUTO_ADD_EXAMPLE_PIPELINE=true
GITEA_EXAMPLE_PIPELINE_REPO=example-pipeline
GITEA_AUTO_ADD_GENERATE_LIBRARY=true
GITEA_GENERATE_LIBRARY_REPO=generate-library
GITEA_GENERATE_LIBRARY_WORKFLOW_SOURCE_REPO_URL=https://github.com/gengelke/playground.git
GITEA_GENERATE_LIBRARY_WORKFLOW_SOURCE_BRANCH=main
GITEA_AUTO_ADD_LIBRARY_EXAMPLE_CLIENT=true
GITEA_LIBRARY_EXAMPLE_CLIENT_REPO=library-example-client
GITEA_LIBRARY_EXAMPLE_CLIENT_WORKFLOW_SOURCE_REPO_URL=https://github.com/gengelke/playground.git
GITEA_LIBRARY_EXAMPLE_CLIENT_WORKFLOW_SOURCE_BRANCH=main
GITEA_LIBRARY_EXAMPLE_CLIENT_WORKFLOW_GRAPHQL_URL=<auto by mode>
GITEA_AUTO_ADD_ADD_EMPLOYEE=true
GITEA_ADD_EMPLOYEE_REPO=add-employee
GITEA_ADD_EMPLOYEE_WORKFLOW_SOURCE_REPO_URL=https://github.com/gengelke/playground.git
GITEA_ADD_EMPLOYEE_WORKFLOW_SOURCE_BRANCH=main
GITEA_ADD_EMPLOYEE_WORKFLOW_GRAPHQL_URL=<auto by mode>
GITEA_AUTO_ADD_PRINT_EMPLOYEE=true
GITEA_PRINT_EMPLOYEE_REPO=print-employee
GITEA_PRINT_EMPLOYEE_WORKFLOW_SOURCE_REPO_URL=https://github.com/gengelke/playground.git
GITEA_PRINT_EMPLOYEE_WORKFLOW_SOURCE_BRANCH=main
GITEA_PRINT_EMPLOYEE_WORKFLOW_GRAPHQL_URL=<auto by mode>
RUNNER1_NAME=agent-runner-1
RUNNER2_NAME=agent-runner-2
RUNNER_LABELS_DOCKER=linux-amd64:docker://node:20-bookworm
RUNNER_LABELS_BARE=linux-amd64:host
```

## Bare mode prerequisites

- `gitea` binary available in `PATH` (or set `GITEA_BIN=/path/to/gitea`)
- `act_runner` binary available in `PATH` (or set `ACT_RUNNER_BIN=/path/to/act_runner`)
- `curl`

## Notes

- Runtime data and generated config are stored in `./runtime/`.
- `make up` ensures both login users exist: `admin/password` and `myuser/password`.
- `make up` also ensures a private repository (`example-pipeline`) exists for `myuser` with branch-specific `Jenkinsfile` content:
  - default branch (`main`/`master`): prints `hello prod world`
  - `dev` branch: prints `hello dev world`
- The same `example-pipeline` repo also gets a managed Gitea Actions workflow at `.gitea/workflows/example-pipeline.yml` on its default and `dev` branches:
  - prints `Hello World` on push and manual dispatch
- Optional: set `GITEA_REMOVE_EXAMPLE_WORKFLOW_REPO=true` to remove the legacy `actions-example` repo during bootstrap.
- `make up` also ensures a private repository (`generate-library`) exists for `myuser` with the managed `Jenkinsfile` on its default and `dev` branches:
  - checks out the configured generate-library source repo (default `https://github.com/gengelke/playground.git`)
  - uses the configured generate-library source branch, defaulting to the job branch
  - runs `make library-generate MODE=bare LIBRARY_SCHEMA_SOURCE=local` in `api/`
  - builds and uploads the `fastapi-graphql-client` package from `api/graphql-library` to the Nexus PyPI repo `pypi-public`
- The same `generate-library` repo also gets a managed Gitea Actions workflow at `.gitea/workflows/generate-library.yml` on its default and `dev` branches:
  - clones the configured generate-library workflow source repo/branch
  - uses managed Gitea Actions secrets `VAULT_ADDR` and `VAULT_TOKEN`
  - fetches Nexus admin credentials from Vault path `secret/data/services/nexus`
  - ensures the Nexus PyPI repo exists
  - runs `make library-generate MODE=bare LIBRARY_SCHEMA_SOURCE=local` in `api/`
  - builds and uploads the `fastapi-graphql-client` package to Nexus
- `make up` also ensures a private repository (`library-example-client`) exists for `myuser` with the managed `Jenkinsfile` on its default and `dev` branches:
  - checks out the configured library-example-client source repo (default `https://github.com/gengelke/playground.git`)
  - starts the FastAPI service in bare mode
  - installs `fastapi-graphql-client` from the Nexus PyPI repo `pypi-public`
  - runs `api/example-client/company.py workflow` using the installed package
- The same `library-example-client` repo also gets a managed Gitea Actions workflow at `.gitea/workflows/library-example-client.yml` on its default and `dev` branches:
  - clones the configured library-example-client workflow source repo/branch
  - uses managed Gitea Actions secrets `VAULT_ADDR` and `VAULT_TOKEN`
  - fetches Nexus read credentials from Vault path `secret/data/services/nexus`
  - installs `fastapi-graphql-client` from the Nexus PyPI repo
  - runs `api/example-client/company.py workflow` with valid role-based data against the shared FastAPI instance
- `GITEA_LIBRARY_EXAMPLE_CLIENT_WORKFLOW_GRAPHQL_URL` defaults by mode:
  - `MODE=docker`: `http://host.docker.internal:8000/graphql`
  - `MODE=bare`: `http://127.0.0.1:8000/graphql`
- `make up` also ensures a private repository (`add-employee`) exists for `myuser` with the managed `Jenkinsfile` on its default and `dev` branches:
  - checks out the configured add-employee source repo (default `https://github.com/gengelke/playground.git`)
  - installs `fastapi-graphql-client` from the Nexus PyPI repo `pypi-public`
  - uses the configured shared FastAPI instance for both the Jenkins role dropdown and the GraphQL mutation call
  - calls `api/example-client/company.py employee add --employee-name ... --employee-surname ... --employee-role ...`
  - is meant to be used from Jenkins with build parameters `EMPLOYEE_NAME`, `EMPLOYEE_SURNAME`, and a role dropdown backed by the FastAPI `GET /roles` API
- `make up` also ensures a private repository (`print-employee`) exists for `myuser` with the managed `Jenkinsfile` on its default and `dev` branches:
  - expects to be used from Jenkins with an Active Choices build parameter named `EMPLOYEE_SELECTION`
  - fetches employee choices from the shared FastAPI GraphQL `employees` query
  - fetches the same GraphQL employee list again during the build and prints the selected employee object to the console log
- The same `print-employee` repo also gets a managed Gitea Actions workflow at `.gitea/workflows/print-employee.yml` on its default and `dev` branches:
  - clones the configured print-employee workflow source repo/branch
  - generates the local GraphQL client runtime from the checked-out source tree
  - runs `api/example-client/company.py employee get` with workflow-dispatch input `employee_id`
  - does not require managed Gitea Actions secrets
- `GITEA_PRINT_EMPLOYEE_WORKFLOW_GRAPHQL_URL` defaults by mode:
  - `MODE=docker`: `http://host.docker.internal:8000/graphql`
  - `MODE=bare`: `http://127.0.0.1:8000/graphql`
- The same `add-employee` repo also gets a managed Gitea Actions workflow at `.gitea/workflows/add-employee.yml` on its default and `dev` branches:
  - clones the configured add-employee workflow source repo/branch
  - uses managed Gitea Actions secrets `VAULT_ADDR` and `VAULT_TOKEN`
  - fetches Nexus credentials from Vault path `secret/data/services/nexus`
  - installs `fastapi-graphql-client` from the Nexus PyPI repo
  - runs `api/example-client/company.py employee add` with workflow-dispatch inputs `employee_name`, `employee_surname`, and `employee_role`
- `GITEA_ADD_EMPLOYEE_WORKFLOW_GRAPHQL_URL` defaults by mode:
  - `MODE=docker`: `http://host.docker.internal:8000/graphql`
  - `MODE=bare`: `http://127.0.0.1:8000/graphql`
- The runner registration token is generated directly from Gitea during bootstrap, persisted in `runtime/shared/generated.env`, and synced to Vault.
- In bare mode, runners are registered once and persisted under `runtime/bare/runner1` and `runtime/bare/runner2`.
- Bootstrap values/secrets are persisted in `runtime/shared/generated.env`.
- If `../vault/.vault/credentials.env` is available and Vault is reachable, credentials are also synced to `secret/data/services/gitea`.

## Cleanup

```bash
make distclean
```

`distclean` removes `runtime/` and `.gitea/`.
