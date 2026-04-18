# DevOps Playground Detailed FAQ

Source: top-level `README.md` in the DevOps Playground repository. Command
names are aligned with the top-level `Makefile`, and host-facing port examples
are aligned with `ports.env`.

## What is the DevOps Playground?

The DevOps Playground is an educational repository for experimenting with local
DevOps tools and workflows. It contains playground setups for multiple services
and topics, including source control, CI/CD, artifact management, secret
management, APIs, reverse proxying, local LLM usage, and a chatbot component.

The playground is intended for isolated local testing. It is not a production
platform and it is not intended to be exposed to the public internet.

## What is the main purpose of the DevOps Playground?

The main purpose is to provide a local learning and experimentation environment
where a developer can start realistic DevOps components, inspect how they work,
connect services together, and test integration patterns without depending on
external infrastructure.

The repository is useful for learning how tools such as Vault, Gitea, GitLab,
Nexus, Jenkins, nginx, FastAPI, Ollama, and the chatbot can run side by side and
interact through local networking, REST APIs, and configuration.

## Is the DevOps Playground safe to expose to the public internet?

No. The playground uses insecure defaults such as default passwords and other
convenience settings. These choices are acceptable for isolated local testing
but not for public, shared, or production environments.

Do not expose any part of the playground to the public internet.

## Was the DevOps Playground generated with AI assistance?

Parts of the repository were generated with AI assistance. Generated code and
configuration should be reviewed carefully before use or modification.

## Which services are included in the DevOps Playground?

The top-level README lists these services:

- `vault`
- `gitea`
- `gitlab`
- `nexus`
- `api`
- `ollama`
- `chatbot`
- `jenkins`
- `nginx`

Each service has its own directory and README. The top-level Makefile can start,
stop, inspect, and clean these services from one place.

## What does the Vault service do?

The `vault` service provides a local HashiCorp Vault OSS environment. It supports
automatic bootstrap and initialization in Docker or bare mode.

Vault represents the playground's secret-management component. Other
Vault-dependent services can verify Vault health during startup. The top-level
README explicitly notes that Gitea, GitLab, Nexus, and Jenkins are
Vault-dependent services.

## What does the Gitea service do?

The `gitea` service provides a local Gitea SCM instance. It includes two action
runners and can run in Docker or bare mode.

Gitea represents a lightweight local source-control and automation system in the
playground. It can be used for repository workflows and runner-based automation.

## What does the GitLab service do?

The `gitlab` service provides a local GitLab CE setup. It includes two GitLab
Runner workers and can run in Docker or bare mode.

GitLab represents a fuller local source-control and CI/CD platform in the
playground.

## What does the Nexus service do?

The `nexus` service provides a local Sonatype Nexus OSS repository manager with
automated first-run initialization.

Nexus represents the artifact repository component of the playground. It can be
used for repository health, artifact, and package-management experiments.

## What does the API service do?

The `api` service provides a FastAPI playground exposing REST and GraphQL
endpoints. It includes client code generation and testing workflows.

The API service is useful for trying REST and GraphQL interactions from other
parts of the playground, including the chatbot.

## What does the Ollama service do?

The `ollama` service provides a local Ollama LLM runtime in Docker. It uses
persistent model storage and automatically pulls the `llama3.1` model.

Ollama can be used by the chatbot as a local LLM provider. The chatbot Makefile
starts the Ollama service and ensures `llama3.1` is available when needed.

## What does the chatbot service do?

The `chatbot` service provides a local-first Python/FastAPI chatbot. It includes
a CLI, REST API, web UI, configurable rules, whitelisted tools, local-file
sources, SQLite document chunks, and optional Qdrant RAG.

The chatbot can run standalone or connect to other playground services through
configuration. Integrations with Jenkins, Gitea, Nexus, Vault, or other services
are configured in `chatbot/config/config.yml`; they are not hardcoded into the
chatbot.

## What does the Jenkins service do?

The `jenkins` service provides a dual Jenkins setup with `prod` and `dev`
instances. It includes preconfigured agents and pipeline bootstrap.

Jenkins represents the CI/CD automation component of the playground.

## What does the nginx service do?

The `nginx` service provides a local HTTPS nginx service. It serves a static
example page with the repository README image.

nginx represents a local reverse proxy or HTTPS frontend component.

## How are the playground services connected?

The top-level README describes the services as a coordinated local playground.
They are connected by local process execution, Docker Compose, shared local
networking, configured URLs, REST APIs, and service-specific configuration.

The chatbot is explicitly designed to connect to other playground services
through configuration instead of hardcoded service names. For example, it can be
configured to query Jenkins, Gitea, Nexus, Vault, or the API service through
local REST endpoints.

Vault-dependent services verify Vault health during startup. The top-level
README names Gitea, GitLab, Nexus, and Jenkins as Vault-dependent services.

## How are host-facing ports configured?

Host-facing ports are managed centrally in `ports.env`.

The documented host port values include:

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
- Ollama: `11434`
- chatbot: `8088`

Update `ports.env` to change ports for all services in one place.

## What shared URLs are defined by the central port configuration?

The central port file defines local URLs such as:

- `VAULT_ADDR=http://127.0.0.1:8200`
- `API_URL=http://127.0.0.1:8000`
- `GITEA_ROOT_URL=http://localhost:3000/`
- `GITLAB_EXTERNAL_URL=http://localhost:8929`
- `NGINX_URL=https://localhost:8443`
- `OLLAMA_URL=http://127.0.0.1:11434`
- `CHATBOT_URL=http://127.0.0.1:8088`

These URLs make it easier for services and users to refer to the same local
endpoints consistently.

## What modes can the playground services use?

The top-level Makefile supports `MODE=docker` and `MODE=bare`.

Use Docker mode when you want services to run through Docker or Docker Compose.
Use bare mode when a service supports running directly on the host with local
dependencies.

Examples:

```bash
make all MODE=docker
make devops MODE=docker
make up-chatbot MODE=docker
make up-vault MODE=bare
```

## How do I start all playground services?

Run:

```bash
make all MODE=docker
```

The alias `make up MODE=docker` starts all services as well.

The top-level Makefile starts all services in the configured start order.

## How do I stop all playground services?

Run:

```bash
make down MODE=docker
```

The aliases `make stop MODE=docker` and `make down MODE=docker` stop services in
reverse order.

## How do I restart all playground services?

Run:

```bash
make restart MODE=docker
```

The restart target runs the stop flow and then the start flow.

## What is the full service start order?

The full service start order is:

```text
vault -> gitea -> gitlab -> nexus -> api -> jenkins -> nginx -> ollama -> chatbot
```

This order is used by the top-level `make all`, `make up`, and `make start`
targets.

## What is the full service stop order?

The full service stop order is:

```text
chatbot -> ollama -> nginx -> jenkins -> api -> nexus -> gitlab -> gitea -> vault
```

This order is used by the top-level `make down` and `make stop` targets.

## How do I start the DevOps scenario subset?

Run:

```bash
make devops MODE=docker
```

The aliases `make devops MODE=docker` and `make devops-up MODE=docker` start the
DevOps scenario subset.

The DevOps scenario starts:

```text
vault -> nexus -> api -> gitea -> jenkins -> nginx -> ollama -> chatbot
```

This subset omits GitLab from the documented DevOps scenario order.

## How do I stop the DevOps scenario subset?

Run:

```bash
make devops-down MODE=docker
```

The alias `make devops-stop MODE=docker` also stops the DevOps scenario subset.

The DevOps scenario stop order is:

```text
chatbot -> ollama -> nginx -> jenkins -> gitea -> api -> nexus -> vault
```

## How do I see the top-level command help?

Run:

```bash
make help
```

The help output describes top-level orchestration commands, DevOps scenario
commands, cleanup commands, and per-service command patterns.

## How do I check the status of all services?

Run:

```bash
make status MODE=docker
```

The top-level status target checks each service in start order.

## How do I start one individual service?

Use the per-service `up-<service>` target:

```bash
make up-vault MODE=docker
make up-gitea MODE=docker
make up-gitlab MODE=docker
make up-nexus MODE=docker
make up-api MODE=docker
make up-jenkins MODE=docker
make up-nginx MODE=docker
make up-ollama MODE=docker
make up-chatbot MODE=docker
```

Each target calls the corresponding service directory's own Makefile with the
same mode.

## How do I stop one individual service?

Use the per-service `down-<service>` target:

```bash
make down-vault MODE=docker
make down-gitea MODE=docker
make down-gitlab MODE=docker
make down-nexus MODE=docker
make down-api MODE=docker
make down-jenkins MODE=docker
make down-nginx MODE=docker
make down-ollama MODE=docker
make down-chatbot MODE=docker
```

Each target stops that one service through the service directory's own Makefile.

## How do I check the status of one individual service?

Use the per-service `status-<service>` target:

```bash
make status-vault MODE=docker
make status-gitea MODE=docker
make status-gitlab MODE=docker
make status-nexus MODE=docker
make status-api MODE=docker
make status-jenkins MODE=docker
make status-nginx MODE=docker
make status-ollama MODE=docker
make status-chatbot MODE=docker
```

## How do I view logs for one individual service?

Use the per-service `logs-<service>` target:

```bash
make logs-vault MODE=docker
make logs-gitea MODE=docker
make logs-gitlab MODE=docker
make logs-nexus MODE=docker
make logs-api MODE=docker
make logs-jenkins MODE=docker
make logs-nginx MODE=docker
make logs-ollama MODE=docker
make logs-chatbot MODE=docker
```

## What does `make up-vault MODE=docker` do?

It starts the Vault service by running the `up` target in the `vault` directory
with `MODE=docker`. Vault is the local secret-management service.

## What does `make up-gitea MODE=docker` do?

It starts the Gitea service by running the `up` target in the `gitea` directory
with `MODE=docker`. Gitea is the local SCM service with action runners.

## What does `make up-gitlab MODE=docker` do?

It starts the GitLab service by running the `up` target in the `gitlab`
directory with `MODE=docker`. GitLab is the local GitLab CE service with two
runner workers.

## What does `make up-nexus MODE=docker` do?

It starts the Nexus service by running the `up` target in the `nexus` directory
with `MODE=docker`. Nexus is the local artifact repository manager.

## What does `make up-api MODE=docker` do?

It starts the API service by running the `up` target in the `api` directory with
`MODE=docker`. The API service exposes REST and GraphQL endpoints.

## What does `make up-jenkins MODE=docker` do?

It starts the Jenkins service by running the `up` target in the `jenkins`
directory with `MODE=docker`. Jenkins provides the dual prod/dev CI setup with
agents and pipeline bootstrap.

## What does `make up-nginx MODE=docker` do?

It starts the nginx service by running the `up` target in the `nginx` directory
with `MODE=docker`. nginx provides the local HTTPS static example page.

## What does `make up-ollama MODE=docker` do?

It starts the Ollama service by running the `up` target in the `ollama`
directory with `MODE=docker`. Ollama provides the local LLM runtime and
automatic `llama3.1` model pull.

## What does `make up-chatbot MODE=docker` do?

It starts the chatbot service by running the `up` target in the `chatbot`
directory with `MODE=docker`. The chatbot provides the CLI, REST API, web UI,
configurable sources, SQLite document chunks, and Qdrant RAG.

## How do I remove generated service state?

Run:

```bash
make distclean
```

The alias `make distclan` also exists.

The cleanup order is:

```text
chatbot -> ollama -> nginx -> jenkins -> api -> nexus -> gitlab -> gitea -> vault
```

This removes generated service state for services that persist local artifacts.

## How do I run the chatbot locally with Python?

Run:

```bash
cd chatbot
make run MODE=bare
```

The chatbot Makefile also starts the Ollama service and pulls `llama3.1` if
needed.

## How do I run the chatbot with Docker Compose?

Run:

```bash
cd chatbot
make up MODE=docker
```

This starts the chatbot Docker setup, including Qdrant. The chatbot Makefile also
starts Ollama when needed.

## Where is the chatbot web UI?

The chatbot web UI is available at:

```text
http://127.0.0.1:8088
```

The same value is represented by `CHATBOT_URL` in the central port
configuration.

## How do I ingest the chatbot sample documents?

Run from the chatbot directory:

```bash
cd chatbot
make ingest PATHS='sample_docs'
```

In Docker mode, the API ingestion endpoint can also ingest `sample_docs` if the
path is visible inside the chatbot container.

## How do I ask the chatbot a question from the CLI?

Run:

```bash
cd chatbot
.venv/bin/python -m app.cli ask "How are you?"
```

## How do I ask the chatbot a question through REST?

Run:

```bash
curl -s http://127.0.0.1:8088/api/chat \
  -H 'Content-Type: application/json' \
  -d '{"message":"How are you?"}'
```

## How can the chatbot use this FAQ?

This FAQ lives in `chatbot/sample_docs`, so it can be used in two ways:

1. As a configured local-file source, when local-file mode is enabled.
2. As RAG input, after ingestion into SQLite and Qdrant.

For RAG usage, ingest the sample documents:

```bash
cd chatbot
make ingest PATHS='sample_docs'
```

Then ask questions in the web UI, CLI, or REST API with RAG enabled.

## What is the difference between local-file mode and RAG mode in the chatbot?

Local-file mode reads configured files directly and returns excerpts. It is
useful for quick deterministic file lookups.

RAG mode retrieves relevant chunks from SQLite and Qdrant and sends that context
to the configured LLM. It is useful for natural-language answers based on
ingested documents.

The web UI treats local-file mode and RAG mode as separate options.

## How does the chatbot connect to Jenkins, Gitea, Nexus, Vault, or other services?

The chatbot does not hardcode dependencies on those services. Integrations are
configured in `chatbot/config/config.yml`.

The top-level README states that integrations with Jenkins, Gitea, Nexus, Vault,
or other local playground services are configured in the chatbot config file.
This keeps external service integration optional and configuration-driven.

## What should I configure if a service port changes?

Update `ports.env` at the repository root. That file centralizes host-facing
ports and derived URLs so service configuration can stay consistent.

## What is the recommended first workflow for a new user?

Start with Docker mode:

```bash
make devops MODE=docker
```

Open the chatbot:

```text
http://127.0.0.1:8088
```

Ingest the sample documents:

```bash
cd chatbot
make ingest PATHS='sample_docs'
```

Ask RAG questions about the playground, such as:

- Which services are included in the DevOps Playground?
- How do I start the DevOps scenario?
- What does the Ollama service do?
- How are ports configured?
- How do I stop Jenkins?

## What is the recommended workflow for starting only the chatbot?

Run:

```bash
cd chatbot
make up MODE=docker
```

Then open:

```text
http://127.0.0.1:8088
```

This is useful when the user only wants the chatbot, Qdrant, and Ollama without
starting the whole playground.

## What is the recommended workflow for working with one service?

Use the top-level per-service targets:

```bash
make up-jenkins MODE=docker
make status-jenkins MODE=docker
make logs-jenkins MODE=docker
make down-jenkins MODE=docker
```

The same command pattern works for Vault, Gitea, GitLab, Nexus, API, nginx,
Ollama, and the chatbot.
