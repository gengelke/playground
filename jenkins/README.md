# Dual Jenkins Setup

> [!WARNING]
> This repository is an experimental setup for educational purposes only.
> Do not expose any part of it to the public internet.
> It uses insecure defaults such as default passwords and other convenience settings that are only acceptable for isolated local testing.

This repository provisions:

- `jenkins-prod` with `jenkins-prod-agent-1` and `jenkins-prod-agent-2`
- `jenkins-dev` with `jenkins-dev-agent-1` and `jenkins-dev-agent-2`

Both instances are configured from the same as-code bootstrap script and differ only by environment values (instance name + branch).

## Behavior

- Shared Git repo for pipeline sources (`PIPELINE_REPO_URL`) or per-instance overrides
  via `PROD_PIPELINE_REPO_URL` and `DEV_PIPELINE_REPO_URL`
- Separate branch per environment:
  - prod instance reads `PROD_BRANCH` (default `main`)
  - dev instance reads `DEV_BRANCH`
- `example-pipeline` is auto-triggered on bootstrap by default; `generate-library`, `library-example-client`, and `add-employee` are created but not auto-triggered by default
- Docker-mode Jenkins agents include the Docker CLI and bind the host Docker socket so pipeline steps can run Docker-backed targets when needed
- Shared automation via `Makefile`
- Two runtime modes:
  - Docker (`docker compose`)
  - Non-Docker (local `java` processes)

## Requirements

- Docker mode: Docker with `docker compose`
- Non-Docker mode: Java 21+ and `curl`

## Quick Start

Both Jenkins instances automatically create and run a pipeline job from git:

- `jenkins-prod` uses `http://host.docker.internal:3000/myuser/example-pipeline` branch `main` by default
- `jenkins-dev` uses `http://host.docker.internal:3000/myuser/example-pipeline` branch `dev` by default
- Both instances check out with Jenkins-managed credentials (`pipeline-git-prod` / `pipeline-git-dev`) when available
- The default `example-pipeline` Jenkinsfile is branch-specific: `main` prints `hello prod world`, `dev` prints `hello dev world`
- Gitea bootstrap also prepares `myuser/generate-library` with Jenkinsfiles that clone the configured generate-library source repo (default `https://github.com/gengelke/playground.git`, branch defaults to the job branch), run `make library-generate MODE=bare LIBRARY_SCHEMA_SOURCE=local` in `api/`, build the `fastapi-graphql-client` package from `api/graphql-library`, and upload it to the Nexus PyPI repo `pypi-public`
- Gitea bootstrap also prepares `myuser/library-example-client` with Jenkinsfiles that clone the configured source repo (default `https://github.com/gengelke/playground.git`, branch defaults to the job branch), start FastAPI in bare mode, install `fastapi-graphql-client` from Nexus PyPI repo `pypi-public`, and run `api/example-client/company.py workflow` using that installed package
- Gitea bootstrap also prepares `myuser/add-employee` with Jenkinsfiles that clone the configured source repo (default `https://github.com/gengelke/playground.git`, branch defaults to the job branch), install `fastapi-graphql-client` from the Nexus PyPI repo `pypi-public`, and run `api/example-client/company.py employee add` against the configured shared FastAPI instance
- The `add-employee` job gets build parameters `EMPLOYEE_NAME`, `EMPLOYEE_SURNAME`, and an Active Choices dropdown `EMPLOYEE_ROLE`; the role values are fetched directly from the FastAPI `GET /roles` API by the Jenkins bootstrap configuration, and the job uses that same FastAPI instance for both its GraphQL call and its Nexus-installed client execution by default
- The example pipeline is remote-triggerable with auth token `example-pipeline-auth-token` by default.

To use your own git repo as Repo A:

```bash
export PIPELINE_REPO_URL=https://github.com/your-org/your-pipeline-repo.git
export PROD_BRANCH=main
export DEV_BRANCH=dev
```

To set a different repo just for `jenkins-dev`:

```bash
export DEV_PIPELINE_REPO_URL=http://host.docker.internal:3000/myuser/example-pipeline
export DEV_PIPELINE_GIT_USERNAME=myuser
export DEV_PIPELINE_GIT_PASSWORD='<gitea-password>'
export DEV_BRANCH=dev
```

Docker mode:

```bash
make up MODE=docker
make status MODE=docker
```

Non-Docker mode:

```bash
make up MODE=bare
make status MODE=bare
```

Default Jenkins accounts are:
- Admin: `admin` / `password`
- Regular user: `user` / `password`
Both Jenkins instances auto-generate a regular-user API token named `jenkins-api-token` (configurable via `JENKINS_REGULAR_API_TOKEN_NAME`).
If `../vault/.vault/credentials.env` is available and Vault is reachable, Jenkins credentials and both instance API tokens are synced to `secret/data/services/jenkins`.

Stop either mode:

```bash
make down MODE=docker
make down MODE=bare
```

## URLs

- `http://127.0.0.1:8081` -> `jenkins-prod`
- `http://127.0.0.1:8082` -> `jenkins-dev`

## Login

- Username defaults to `admin` (`JENKINS_ADMIN_USER`).
- Password defaults to `password` (`JENKINS_ADMIN_PASSWORD`).
- Regular username defaults to `user` (`JENKINS_REGULAR_USER`).
- Regular password defaults to `password` (`JENKINS_REGULAR_PASSWORD`).

## Main Targets

- `make up MODE=docker|bare`
- `make down MODE=docker|bare`
- `make restart MODE=docker|bare`
- `make logs MODE=docker|bare`
- `make status MODE=docker|bare`
- `make distclean`

## Remote Trigger

The `example-pipeline` job is configured with remote auth token `example-pipeline-auth-token`.
Use an authenticated Jenkins user plus that token, for example:

```bash
curl -u admin:password "http://127.0.0.1:8081/job/example-pipeline/build?token=example-pipeline-auth-token"
```

## Tunables

- `PIPELINE_REPO_URL`
- `PROD_PIPELINE_REPO_URL` (optional override for prod)
- `DEV_PIPELINE_REPO_URL` (optional override for dev)
- `PIPELINE_GIT_CREDENTIALS_ID` (shared optional git credentials id)
- `PIPELINE_GIT_USERNAME` (shared optional git username)
- `PIPELINE_GIT_PASSWORD` (shared optional git password)
- `PROD_PIPELINE_GIT_CREDENTIALS_ID` / `PROD_PIPELINE_GIT_USERNAME` / `PROD_PIPELINE_GIT_PASSWORD`
- `DEV_PIPELINE_GIT_CREDENTIALS_ID` / `DEV_PIPELINE_GIT_USERNAME` / `DEV_PIPELINE_GIT_PASSWORD`
- `GENERATE_LIBRARY_PIPELINE_REPO_URL` (shared optional override for `generate-library`)
- `PROD_GENERATE_LIBRARY_PIPELINE_REPO_URL` / `DEV_GENERATE_LIBRARY_PIPELINE_REPO_URL`
- `GENERATE_LIBRARY_PIPELINE_BRANCH` (shared optional branch override)
- `PROD_GENERATE_LIBRARY_PIPELINE_BRANCH` / `DEV_GENERATE_LIBRARY_PIPELINE_BRANCH`
- `GENERATE_LIBRARY_SOURCE_REPO_URL` (shared source checkout override used inside the `generate-library` job)
- `PROD_GENERATE_LIBRARY_SOURCE_REPO_URL` / `DEV_GENERATE_LIBRARY_SOURCE_REPO_URL`
- `GENERATE_LIBRARY_SOURCE_BRANCH` (shared source branch override; default matches the generate-library job branch)
- `PROD_GENERATE_LIBRARY_SOURCE_BRANCH` / `DEV_GENERATE_LIBRARY_SOURCE_BRANCH`
- `LIBRARY_EXAMPLE_CLIENT_PIPELINE_REPO_URL` (shared optional override for `library-example-client`)
- `PROD_LIBRARY_EXAMPLE_CLIENT_PIPELINE_REPO_URL` / `DEV_LIBRARY_EXAMPLE_CLIENT_PIPELINE_REPO_URL`
- `LIBRARY_EXAMPLE_CLIENT_PIPELINE_BRANCH` (shared optional branch override)
- `PROD_LIBRARY_EXAMPLE_CLIENT_PIPELINE_BRANCH` / `DEV_LIBRARY_EXAMPLE_CLIENT_PIPELINE_BRANCH`
- `LIBRARY_EXAMPLE_CLIENT_SOURCE_REPO_URL` (shared source checkout override used inside the `library-example-client` job)
- `PROD_LIBRARY_EXAMPLE_CLIENT_SOURCE_REPO_URL` / `DEV_LIBRARY_EXAMPLE_CLIENT_SOURCE_REPO_URL`
- `LIBRARY_EXAMPLE_CLIENT_SOURCE_BRANCH` (shared source branch override; default matches the `library-example-client` job branch)
- `PROD_LIBRARY_EXAMPLE_CLIENT_SOURCE_BRANCH` / `DEV_LIBRARY_EXAMPLE_CLIENT_SOURCE_BRANCH`
- `ADD_EMPLOYEE_PIPELINE_REPO_URL` (shared optional override for `add-employee`)
- `PROD_ADD_EMPLOYEE_PIPELINE_REPO_URL` / `DEV_ADD_EMPLOYEE_PIPELINE_REPO_URL`
- `ADD_EMPLOYEE_PIPELINE_BRANCH` (shared optional branch override)
- `PROD_ADD_EMPLOYEE_PIPELINE_BRANCH` / `DEV_ADD_EMPLOYEE_PIPELINE_BRANCH`
- `ADD_EMPLOYEE_SOURCE_REPO_URL` (shared source checkout override used inside the `add-employee` job)
- `PROD_ADD_EMPLOYEE_SOURCE_REPO_URL` / `DEV_ADD_EMPLOYEE_SOURCE_REPO_URL`
- `ADD_EMPLOYEE_SOURCE_BRANCH` (shared source branch override; default matches the `add-employee` job branch)
- `PROD_ADD_EMPLOYEE_SOURCE_BRANCH` / `DEV_ADD_EMPLOYEE_SOURCE_BRANCH`
- `ADD_EMPLOYEE_FASTAPI_ROLES_URL` (shared override for the controller-side role dropdown source; default points to FastAPI `GET /roles`)
- `PROD_ADD_EMPLOYEE_FASTAPI_ROLES_URL` / `DEV_ADD_EMPLOYEE_FASTAPI_ROLES_URL`
- `ADD_EMPLOYEE_GRAPHQL_URL` (shared override used inside the `add-employee` job; default derived from `ADD_EMPLOYEE_FASTAPI_ROLES_URL`)
- `PROD_ADD_EMPLOYEE_GRAPHQL_URL` / `DEV_ADD_EMPLOYEE_GRAPHQL_URL`
- `PROD_BRANCH` (default `main`)
- `DEV_BRANCH`
- `PIPELINE_SCRIPT_PATH` (default `Jenkinsfile`)
- `PIPELINE_JOB_NAME` (default `example-pipeline`)
- `PIPELINE_AUTH_TOKEN` (default `example-pipeline-auth-token`)
- `PIPELINE_AUTO_TRIGGER` (default `true`)
- `GENERATE_LIBRARY_PIPELINE_AUTO_TRIGGER` (default `false`)
- `LIBRARY_EXAMPLE_CLIENT_PIPELINE_JOB_NAME` (default `library-example-client`)
- `LIBRARY_EXAMPLE_CLIENT_PIPELINE_AUTH_TOKEN` (default empty)
- `LIBRARY_EXAMPLE_CLIENT_PIPELINE_AUTO_TRIGGER` (default `false`)
- `ADD_EMPLOYEE_PIPELINE_JOB_NAME` (default `add-employee`)
- `ADD_EMPLOYEE_PIPELINE_AUTH_TOKEN` (default empty)
- `ADD_EMPLOYEE_PIPELINE_AUTO_TRIGGER` (default `false`)
- `AGENT_COUNT` (default `2`)
- `AGENT_EXECUTORS` (default `1`)
- `PROD_HTTP_PORT` (default `8081`)
- `DEV_HTTP_PORT` (default `8082`)
- `PROD_JENKINS_ROOT_URL` (default `http://127.0.0.1:8081/`)
- `DEV_JENKINS_ROOT_URL` (default `http://127.0.0.1:8082/`)
- `JENKINS_ADMIN_USER` (default `admin`)
- `JENKINS_ADMIN_PASSWORD` (default `password`)
- `JENKINS_REGULAR_USER` (default `user`)
- `JENKINS_REGULAR_PASSWORD` (default `password`)
- `JENKINS_REGULAR_API_TOKEN_NAME` (default `jenkins-api-token`)
- `JENKINS_CSP` (optional override; leave unset to use Jenkins default and avoid DirectoryBrowserSupport.CSP warning)
- `JENKINS_TIMEZONE` (default `Europe/Berlin`)
- `VAULT_ADDR` (auto-resolved; docker defaults to `http://host.docker.internal:8200`)
- `VAULT_TOKEN` (auto-resolved from `../vault/.vault/credentials.env` when available)
- `NEXUS_PYPI_REPO` (optional; default `pypi-public` in the generated Jenkinsfile)

Example override:

```bash
make up MODE=docker PIPELINE_REPO_URL=https://github.com/acme/ci.git PROD_BRANCH=release DEV_BRANCH=develop
```

Per-instance repo override example:

```bash
make up MODE=docker \
  PROD_PIPELINE_REPO_URL=https://github.com/acme/ci.git \
  DEV_PIPELINE_REPO_URL=http://host.docker.internal:3000/myuser/example-pipeline \
  DEV_PIPELINE_GIT_USERNAME=myuser \
  DEV_PIPELINE_GIT_PASSWORD='<gitea-password>' \
  DEV_GENERATE_LIBRARY_SOURCE_REPO_URL=https://github.com/acme/playground.git \
  DEV_LIBRARY_EXAMPLE_CLIENT_SOURCE_REPO_URL=https://github.com/acme/playground.git \
  PROD_BRANCH=release \
  DEV_BRANCH=dev
```

## Note

Both Jenkins instances are initialized automatically, including nodes/agents and login setup.
`make distclean` removes `.state/`.
