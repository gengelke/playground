# Dual Jenkins Setup

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
- Shared automation via `Makefile`
- Two runtime modes:
  - Docker (`docker compose`)
  - Non-Docker (local `java` processes)

## Requirements

- Docker mode: Docker with `docker compose`
- Non-Docker mode: Java 17+ and `curl`

## Quick Start

If `PIPELINE_REPO_URL` is unset, startup automatically creates local **Repo A** at
`.state/repo-a` (git repository with branches `main` + `dev`) and a `Jenkinsfile`
that prints `hello world` on an attached agent (`label 'linux'`).

Both Jenkins instances automatically create and run a pipeline job from git:

- `jenkins-prod` uses `http://host.docker.internal:3000/myuser/jenkins-example` branch `main` by default
- `jenkins-dev` uses `http://host.docker.internal:3000/myuser/jenkins-example` branch `dev` by default
- Both instances check out with Jenkins-managed credentials (`pipeline-git-prod` / `pipeline-git-dev`) when available
- The example pipeline is remote-triggerable with auth token `example-pipeline-auth-token` by default.

To use your own git repo as Repo A:

```bash
export PIPELINE_REPO_URL=https://github.com/your-org/your-pipeline-repo.git
export PROD_BRANCH=main
export DEV_BRANCH=dev
```

To set a different repo just for `jenkins-dev`:

```bash
export DEV_PIPELINE_REPO_URL=http://host.docker.internal:3000/myuser/jenkins-example
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
- `PROD_BRANCH` (default `main`)
- `DEV_BRANCH`
- `PIPELINE_SCRIPT_PATH` (default `Jenkinsfile`)
- `PIPELINE_JOB_NAME` (default `example-pipeline`)
- `PIPELINE_AUTH_TOKEN` (default `example-pipeline-auth-token`)
- `AGENT_COUNT` (default `2`)
- `AGENT_EXECUTORS` (default `1`)
- `PROD_HTTP_PORT` (default `8081`)
- `DEV_HTTP_PORT` (default `8082`)
- `JENKINS_ADMIN_USER` (default `admin`)
- `JENKINS_ADMIN_PASSWORD` (default `password`)
- `JENKINS_REGULAR_USER` (default `user`)
- `JENKINS_REGULAR_PASSWORD` (default `password`)
- `JENKINS_REGULAR_API_TOKEN_NAME` (default `jenkins-api-token`)

Example override:

```bash
make up MODE=docker PIPELINE_REPO_URL=https://github.com/acme/ci.git PROD_BRANCH=release DEV_BRANCH=develop
```

Per-instance repo override example:

```bash
make up MODE=docker \
  PROD_PIPELINE_REPO_URL=https://github.com/acme/ci.git \
  DEV_PIPELINE_REPO_URL=http://host.docker.internal:3000/myuser/jenkins-example \
  DEV_PIPELINE_GIT_USERNAME=myuser \
  DEV_PIPELINE_GIT_PASSWORD='<gitea-password>' \
  PROD_BRANCH=release \
  DEV_BRANCH=dev
```

## Note

Both Jenkins instances are initialized automatically, including nodes/agents and login setup.
