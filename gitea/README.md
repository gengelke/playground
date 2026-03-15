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
GITEA_AUTO_ADD_EXAMPLE_WORKFLOW=true
GITEA_EXAMPLE_REPO=actions-example
GITEA_REMOVE_EXAMPLE_WORKFLOW_REPO=false
GITEA_AUTO_ADD_JENKINS_EXAMPLE=true
GITEA_JENKINS_EXAMPLE_REPO=jenkins-example
GITEA_AUTO_ADD_GENERATE_LIBRARY=true
GITEA_GENERATE_LIBRARY_REPO=generate-library
GITEA_AUTO_ADD_LIBRARY_EXAMPLE_CLIENT=true
GITEA_LIBRARY_EXAMPLE_CLIENT_REPO=library-example-client
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
- `make up` ensures a private `actions-example` repository exists by default and writes `.gitea/workflows/actions-example.yml`.
- The `actions-example` workflow prints `hello world` on push and manual dispatch.
- Optional: set `GITEA_REMOVE_EXAMPLE_WORKFLOW_REPO=true` to remove `actions-example` during bootstrap.
- `make up` also ensures a private repository (`jenkins-example`) exists for `myuser` with branch-specific `Jenkinsfile` content:
  - default branch (`main`/`master`): prints `hello prod world`
  - `dev` branch: prints `hello dev world`
- `make up` also ensures a private repository (`generate-library`) exists for `myuser` with the managed `Jenkinsfile` on its default and `dev` branches:
  - checks out the configured generate-library source repo (default `https://github.com/gengelke/playground.git`)
  - uses the configured generate-library source branch, defaulting to the job branch
  - runs `make library-generate MODE=bare LIBRARY_SCHEMA_SOURCE=local` in `api/`
  - builds and uploads the `fastapi-graphql-client` package from `api/graphql-library` to the Nexus PyPI repo `pypi-public`
- `make up` also ensures a private repository (`library-example-client`) exists for `myuser` with the managed `Jenkinsfile` on its default and `dev` branches:
  - checks out the configured library-example-client source repo (default `https://github.com/gengelke/playground.git`)
  - starts the FastAPI service in bare mode
  - installs `fastapi-graphql-client` from the Nexus PyPI repo `pypi-public`
  - runs `api/example-client/company.py` using the installed package
- The runner registration token is generated directly from Gitea during bootstrap, persisted in `runtime/shared/generated.env`, and synced to Vault.
- In bare mode, runners are registered once and persisted under `runtime/bare/runner1` and `runtime/bare/runner2`.
- Bootstrap values/secrets are persisted in `runtime/shared/generated.env`.
- If `../vault/.vault/credentials.env` is available and Vault is reachable, credentials are also synced to `secret/data/services/gitea`.

## Cleanup

```bash
make distclean
```

`distclean` removes `runtime/` and `.gitea/`.
