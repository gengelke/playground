# DevOps Playground Detailed FAQ

Source: top-level `README.md`, service READMEs, top-level `Makefile`,
`ports.env`, and the repository git history. This file is intended as example
input for the chatbot. It can be used as a configured local file or ingested
into SQLite/Qdrant RAG.

## Who is the author of the DevOps Playground?

Gordon Engelke is the author and maintainer of the DevOps Playground.

The repository git history shows the first commit as:

```text
356b050 2026-03-06 Gordon Engelke Create README.md
```

For this FAQ, the DevOps Playground is considered to have been born on
2026-03-06, based on that first commit date.

## What is the DevOps Playground?

The DevOps Playground is an educational local playground for experimenting with
DevOps services, automation workflows, APIs, package management, secret
management, local LLM usage, and chatbot-assisted operations.

It is intentionally local-first. The goal is to make it easy to start realistic
tooling on a developer machine, inspect how the parts work, connect services
together, and test workflows without relying on shared or production
infrastructure.

The playground is experimental. It uses insecure defaults such as default
passwords and convenience settings. It must not be exposed to the public
internet.

## Was the DevOps Playground generated with AI assistance?

Parts of the repository were generated with AI assistance. The repository
README and service READMEs include an AI assistance notice. Generated code and
configuration should be reviewed carefully before being used or modified.

## Which services are included?

The playground currently contains these top-level service components:

- `vault`
- `gitea`
- `gitlab`
- `nexus`
- `api`
- `jenkins`
- `nginx`
- `qdrant`
- `ollama`
- `chatbot`

Each service has its own directory, README, and Makefile. The top-level
Makefile can orchestrate all services or start and stop individual services.

## What is the difference between `make all` and `make devops`?

`make all MODE=docker` starts every service in the playground:

```text
vault -> gitea -> gitlab -> nexus -> api -> jenkins -> nginx -> qdrant -> ollama -> chatbot
```

`make devops MODE=docker` starts the smaller DevOps scenario subset:

```text
vault -> nexus -> api -> gitea -> jenkins -> nginx -> qdrant -> ollama -> chatbot
```

The DevOps scenario intentionally does not start `gitlab`. Use `make all` or
`make up-gitlab` when GitLab should be included.

## How do I start every service?

Run from the repository root:

```bash
make all MODE=docker
```

`make up MODE=docker` is an alias for the same all-service startup flow.

## How do I stop every service?

Run from the repository root:

```bash
make down MODE=docker
```

The full stop order is:

```text
chatbot -> ollama -> nginx -> jenkins -> api -> nexus -> gitlab -> gitea -> vault
```

## How do I start or stop one service?

Use the top-level per-service targets:

```bash
make up-vault MODE=docker
make down-vault MODE=docker
make status-vault MODE=docker
make logs-vault MODE=docker
```

The same pattern exists for all services:

```text
vault gitea gitlab nexus api jenkins nginx qdrant ollama chatbot
```

Examples:

```bash
make up-gitea MODE=docker
make status-gitlab MODE=docker
make logs-chatbot MODE=docker
make down-nginx MODE=docker
```

You can also work inside a service directory:

```bash
cd chatbot
make up MODE=docker
```

## How are ports configured?

Host-facing ports are centralized in `ports.env`.

Current default ports:

- Vault: `8200`
- API: `8000`
- Gitea HTTP: `3000`
- Gitea SSH: `2222`
- GitLab HTTP: `8929`
- GitLab SSH: `2224`
- Nexus HTTP: `8083`
- Jenkins prod HTTP: `8081`
- Jenkins dev HTTP: `8082`
- nginx HTTPS: `8443`
- Ollama: `11435`
- chatbot: `8088`

The same file defines shared URLs such as:

```text
VAULT_ADDR=http://127.0.0.1:8200
API_URL=http://127.0.0.1:8000
GITEA_ROOT_URL=http://localhost:3000/
GITLAB_EXTERNAL_URL=http://localhost:8929
NGINX_URL=https://localhost:8443
OLLAMA_URL=http://127.0.0.1:11435
CHATBOT_URL=http://127.0.0.1:8088
```

## What does the Vault service do?

The `vault` service provides a local HashiCorp Vault OSS environment. It is the
secret-management component of the playground.

Vault can run in Docker mode or bare mode. Its Makefile starts Vault, waits for
the API, initializes Vault on first startup, stores generated credentials under
`.vault/credentials.env`, unseals Vault, creates a `secret/` KV v2 mount, enables
`userpass` auth, and configures default users.

Default users:

- `admin` / `password`
- `user` / `password`

Other services can sync generated credentials into Vault when
`../vault/.vault/credentials.env` is available and Vault is reachable. The
playground treats Gitea, GitLab, Nexus, and Jenkins as Vault-dependent services.

Common usage:

```bash
cd vault
make up MODE=docker
make status MODE=docker
make creds
make down MODE=docker
```

## What does the Gitea service do?

The `gitea` service provides a local Gitea source-control instance with two
action runners. It is the lightweight SCM and runner-based automation component
of the playground.

Gitea can run in Docker mode or bare mode. First-run initialization is
automatic. The service creates managed users, prepares repositories, and can
attach runners for workflow execution.

The Gitea setup can prepare repositories such as:

- `example-pipeline`
- `playground`
- `generate-library`
- `library-example-client`
- `add-employee`
- `print-employee`

Those repositories are used by Jenkins and API-related workflows. For example,
Jenkins jobs can clone local Gitea repositories, run pipeline logic, generate a
GraphQL client, upload packages to Nexus, and call the FastAPI service.

Common usage:

```bash
cd gitea
make up MODE=docker
make logs MODE=docker
make status MODE=docker
make down MODE=docker
```

## What does the GitLab service do?

The `gitlab` service provides a local GitLab CE setup with two GitLab Runner
workers. It is the fuller local SCM and CI/CD platform option in the playground.

GitLab can run in Docker mode or bare mode. Docker mode starts GitLab CE and two
runner workers. Bare mode uses host OS installation scripts intended for a
Debian/Ubuntu-style environment.

Default GitLab access:

- Web: `http://localhost:8929`
- SSH: port `2224`
- Admin user: `admin`
- Regular user: `user`

The GitLab setup creates or syncs managed users, prints generated credentials,
and can sync credentials into Vault when Vault is available.

Common usage:

```bash
cd gitlab
make up MODE=docker
make status MODE=docker
make logs MODE=docker
make down MODE=docker
```

## What does the Nexus service do?

The `nexus` service provides a local Sonatype Nexus OSS repository manager. It
is the artifact and package repository component of the playground.

Nexus can run in Docker mode or bare mode. Its startup flow waits for Nexus to
be healthy, accepts the Community Edition EULA when required, creates managed
users, configures anonymous access, and ensures a hosted PyPI repository named
`pypi-public` exists.

The playground uses Nexus for package-management experiments. Jenkins and API
workflows can generate a Python GraphQL client package and upload it to the
Nexus PyPI repository. Other workflows can then install the generated package
from Nexus.

Default Nexus URL:

```text
http://localhost:8083
```

Common usage:

```bash
cd nexus
make up MODE=docker
make status MODE=docker
make logs MODE=docker
make down MODE=docker
```

## What does the API service do?

The `api` service provides the FastAPI playground. It exposes REST and GraphQL
endpoints and includes tooling for generated GraphQL client workflows.

The API directory contains:

- `fastapi/`: REST and GraphQL service
- `graphql-library/`: generated Python GraphQL client package
- `example-client/`: CLI workflow client that exercises the API and generated package

FastAPI requires HTTP Basic Auth on REST, GraphQL, docs, and schema endpoints.
The health endpoint remains unauthenticated for readiness checks.

Default credentials:

- `FASTAPI_BASIC_AUTH_USERNAME=admin`
- `FASTAPI_BASIC_AUTH_PASSWORD=password`

Useful API examples:

- `GET /employees`
- `GET /employees/{employee_id}`
- `POST /employees`
- `PUT /employees/{employee_id}`
- `DELETE /employees/{employee_id}`
- `GET /roles`
- GraphQL employee and role operations

The API service is used by Jenkins and Gitea workflow examples. Jenkins jobs can
call FastAPI directly, fetch roles for Active Choices parameters, run generated
client workflows, and use packages installed from Nexus.

Common usage:

```bash
cd api
make up MODE=docker
make library-generate MODE=docker
make run MODE=docker
make down MODE=docker
```

## What does the Jenkins service do?

The `jenkins` service provides a dual Jenkins setup:

- `jenkins-prod`
- `jenkins-dev`

Each instance has agents and is configured from shared as-code bootstrap logic.
The instances differ by environment values such as instance name and branch.

Jenkins is the CI/CD automation component of the playground. It can clone local
Gitea repositories, run branch-specific pipelines, generate client libraries,
upload generated packages to Nexus, call FastAPI endpoints, and run jobs with
parameters populated from API data.

Important Jenkins behavior:

- `jenkins-prod` defaults to branch `main`
- `jenkins-dev` defaults to branch `dev`
- Docker-mode agents include the Docker CLI and bind the host Docker socket
- managed jobs can clone local Gitea repositories
- generated client workflows can publish to Nexus
- jobs can call FastAPI using shared Basic Auth credentials
- credentials can be synced with Vault when available

Default Jenkins URLs:

- prod: `http://127.0.0.1:8081`
- dev: `http://127.0.0.1:8082`

Common usage:

```bash
cd jenkins
make up MODE=docker
make status MODE=docker
make logs MODE=docker
make down MODE=docker
```

## What does the nginx service do?

The `nginx` service provides a local HTTPS endpoint. It serves a static example
page and displays the same image referenced at the top of the repository
README.

Startup generates a local self-signed TLS certificate under:

```text
nginx/.state/tls/
```

Browsers will warn because the certificate is self-signed. That warning is
expected for local testing.

Default URL:

```text
https://localhost:8443
```

Common usage:

```bash
cd nginx
make up MODE=docker
make status MODE=docker
make logs MODE=docker
make down MODE=docker
```

## What does the Qdrant service do?

The `qdrant` service provides a local Qdrant vector database. It is the vector
storage component used by the chatbot's Qdrant RAG profiles, and it can also be
used independently by other playground experiments.

The Qdrant service keeps collections on the host under:

```text
qdrant/data
```

That host directory is mounted into the container as `/qdrant/storage`, so
collections survive container restarts and container recreation.

Default host URL:

```text
http://127.0.0.1:6333
```

Docker chatbot integration URL:

```text
http://playground-qdrant:6333
```

Common usage:

```bash
cd qdrant
make up MODE=docker
make status MODE=docker
make logs MODE=docker
make down MODE=docker
```

## What does the Ollama service do?

The `ollama` service provides a local Ollama LLM runtime in Docker. It is the
local LLM component used by the chatbot.

The Ollama service keeps pulled models on the host under:

```text
ollama/data
```

That host directory is mounted into the container as `/root/.ollama`, so model
downloads survive container restarts and container recreation.

The Makefile starts the Ollama container, waits for `/api/tags`, and pulls the
configured model. By default, that model is:

```text
llama3.1
```

The chatbot also uses Ollama embeddings when the `qdrant_ollama` retrieval
profile is selected. The chatbot Makefile ensures `nomic-embed-text` is pulled
when needed.

Default URL:

```text
http://127.0.0.1:11435
```

Docker chatbot integration URL:

```text
http://playground-ollama:11434/api/chat
```

Common usage:

```bash
cd ollama
make up MODE=docker
make pull-model OLLAMA_MODEL=llama3.1
make status MODE=docker
make down MODE=docker
```

## What does the chatbot service do?

The `chatbot` service provides a local-first Python 3.12 chatbot with:

- CLI interface
- FastAPI REST API
- simple browser UI
- question history
- one-click copy buttons in the web UI
- deterministic configured rules
- regex rules
- whitelisted host commands
- local file sources
- configured SQLite sources
- configured REST sources
- SQLite document chunk storage
- optional Qdrant RAG
- configurable LLM providers
- retrieval and embedding comparison profiles

The chatbot is intended to remain useful standalone, but it can also connect to
other playground services through configuration. Integrations are not hardcoded.
For example, REST sources for Jenkins, Gitea, Nexus, Vault, or the API service
can be configured in `chatbot/config/config.yml`.

The chatbot request pipeline checks deterministic paths before using an LLM. It
only calls the selected LLM when deterministic rules, tools, local sources, and
retrieval paths are insufficient or when generative behavior is explicitly
needed.

Default web UI:

```text
http://127.0.0.1:8088
```

Common usage:

```bash
cd chatbot
make up MODE=docker
make ingest PATHS='sample_docs'
.venv/bin/python -m app.cli ask "How are you?"
.venv/bin/python -m app.cli history list --limit 20
curl -s http://127.0.0.1:8088/api/chat \
  -H 'Content-Type: application/json' \
  -d '{"message":"How are you?"}'
```

The chatbot web UI is available at:

```text
http://127.0.0.1:8088/chat
```

The ingestion UI is available at:

```text
http://127.0.0.1:8088/ingest
```

The chat page includes a history panel. Selecting an entry or pressing `Use`
copies only the selected historical question into the question field; it does
not send the question automatically.

The chatbot also exposes history through REST:

```bash
curl -s http://127.0.0.1:8088/api/history?limit=20
curl -s -X DELETE http://127.0.0.1:8088/api/history
```

Configured `Simon says` commands include:

- `Simon says get time`: prints the current system time.
- `Simon says get statistics`: prints SQLite ingestion summaries, duplicate
  chunk checks, and Qdrant collection status.
- `Simon says get docs`: lists files in the example document directory.
- `Simon says get employees`: uses the generated GraphQL client library to list
  employees from the API service.
- `Simon says add employee <name> <surname> <role>`: adds an employee through
  the API service. Quote roles with spaces, for example `Simon says add
  employee Erika Mustermann "Senior Developer"`.
- `Simon says delete employee <employeeId>`: deletes an employee through the
  API service.

## How can the chatbot compare local files, SQLite, and Qdrant?

The chatbot supports retrieval profiles. They make it possible to ask the same
question against different knowledge sources and embedding strategies.

Default retrieval profiles include:

- `local_files`
- `sqlite`
- `hybrid`
- `qdrant_local_hash`
- `qdrant_openai`
- `qdrant_ollama`
- `qdrant_anthropic_openai`

This makes the chatbot useful for comparing answer quality and efficiency when
using:

- direct local files
- SQLite token-based chunk retrieval
- Qdrant with the built-in local hash embedding
- Qdrant with OpenAI embeddings
- Qdrant with Ollama embeddings
- Qdrant with OpenAI embeddings used for Anthropic-style retrieval

Example compare call:

```bash
curl -s http://127.0.0.1:8088/api/chat/compare \
  -H 'Content-Type: application/json' \
  -d '{
    "message": "Who maintains the playground?",
    "provider": "openai",
    "model": "gpt-4.1-mini",
    "retrieval_profiles": ["sqlite", "qdrant_local_hash", "qdrant_openai"]
  }'
```

The response includes the answer, selected retrieval profile, provider/model,
retrieved context, and timing metadata.

## How are the services connected?

The services are connected through local networking, Docker Compose networks,
shared host ports, configured URLs, REST APIs, generated credentials, and common
Makefile orchestration.

Important examples:

- Vault stores and shares generated service credentials when available.
- Gitea provides local repositories and action runners.
- GitLab provides an alternate local SCM and CI/CD system.
- Nexus stores generated packages such as the GraphQL client package.
- FastAPI exposes REST and GraphQL endpoints used by example clients and Jenkins jobs.
- Jenkins clones local repositories, runs pipelines, calls FastAPI, and publishes packages to Nexus.
- nginx provides a local HTTPS frontend example.
- Ollama provides local LLM inference for the chatbot.
- The chatbot can query configured services through REST APIs and use local docs as knowledge.

## How do I remove generated state?

Run from the repository root:

```bash
make distclean
```

The cleanup order is:

```text
chatbot -> ollama -> nginx -> jenkins -> api -> nexus -> gitlab -> gitea -> vault
```

`make distclan` is available as an alias.

## How can this FAQ be used by the chatbot?

This FAQ is stored in:

```text
chatbot/sample_docs/playground-faq.md
```

It can be used in two ways:

1. As a configured local-file source when local-file mode is enabled.
2. As RAG input after ingestion into SQLite and Qdrant.

To ingest the sample documents:

```bash
cd chatbot
make ingest PATHS='sample_docs'
```

For a clean RAG rebuild through the API:

```bash
curl -sS http://127.0.0.1:8088/api/ingest \
  -H 'Content-Type: application/json' \
  -d '{"paths":["sample_docs"],"reset":true}'
```

After ingestion, ask questions such as:

- Who is the author of the DevOps Playground?
- When was the DevOps Playground born?
- Which services are included in the playground?
- What does Jenkins do in the playground?
- How does Nexus connect to Jenkins and the API service?
- How can the chatbot compare SQLite and Qdrant retrieval?
