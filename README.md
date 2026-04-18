<img width="1536" height="1024" alt="playground" src="https://github.com/user-attachments/assets/cb0e795a-50a6-44a5-b872-24ad7eecbd54" />
<br><br>

<h4><p align="center">This repository is for educational purposes. It contains playground setups for various tools & topics</p></h4>

> [!WARNING]
> This repository is an experimental setup for educational purposes only.
> Do not expose any part of it to the public internet.
> It uses insecure defaults such as default passwords and other convenience settings that are only acceptable for isolated local testing.

> [!IMPORTANT]
> Parts of this repository were generated with AI assistance.
> Review generated code and configuration carefully before using or modifying it.

## Services

- `vault`: Local HashiCorp Vault OSS environment with automatic bootstrap/init in docker or bare mode. <BR>
See [vault/README.md](vault/README.md).
- `gitea`: Local Gitea SCM instance with two action runners, available in docker or bare mode. <BR>
See [gitea/README.md](gitea/README.md).
- `gitlab`: Local GitLab CE setup with two GitLab Runner workers in docker or bare mode. <BR>
See [gitlab/README.md](gitlab/README.md).
- `nexus`: Local Sonatype Nexus OSS repository manager with automated first-run initialization. <BR>
See [nexus/README.md](nexus/README.md).
- `api`: FastAPI playground exposing REST and GraphQL endpoints, including client code generation/testing workflows. <BR>
See [api/README.md](api/README.md).
- `ollama`: Local Ollama LLM runtime in Docker with persistent model storage and automatic `llama3.1` pull. <BR>
See [ollama/README.md](ollama/README.md).
- `chatbot`: Local-first Python/FastAPI chatbot with CLI, REST API, web UI, configurable rules/tools/sources, SQLite document chunks, and optional Qdrant RAG. It can run standalone or connect to other playground services through config. <BR>
See [chatbot/README.md](chatbot/README.md).
- `jenkins`: Dual Jenkins setup (`prod` and `dev`) with preconfigured agents and pipeline bootstrap. <BR>
See [jenkins/README.md](jenkins/README.md).
- `nginx`: Local HTTPS nginx service serving a static example page with the repository README image. <BR>
See [nginx/README.md](nginx/README.md).

## Chatbot quick start

The chatbot is an optional playground component. It is useful for trying a
simple local-first assistant that can answer deterministic configured rules,
run explicitly whitelisted commands, read local documents, query configured
SQLite/REST sources, and use Qdrant plus the local Ollama LLM.

Run locally with a Python virtual environment:

```bash
cd chatbot
make run MODE=bare
```

The chatbot Makefile also starts the `ollama` service and pulls `llama3.1` if
needed.

Run with Docker Compose, including Qdrant:

```bash
cd chatbot
make up MODE=docker
```

Open the web UI at:

```text
http://127.0.0.1:8088
```

CLI and REST examples:

```bash
cd chatbot
make ingest PATHS='sample_docs'
.venv/bin/python -m app.cli ask "How are you?"
curl -s http://127.0.0.1:8088/api/chat \
  -H 'Content-Type: application/json' \
  -d '{"message":"How are you?"}'
```

Integrations with Jenkins, Gitea, Nexus, Vault, or other local playground
services are configured in `chatbot/config/config.yml`; they are not hardcoded
into the chatbot.

## Top-level orchestration

A top-level `Makefile` can orchestrate all services, including Ollama and the
chatbot.

Start all services in dependency order:

```bash
make all MODE=docker
```

Stop all services in reverse dependency order:

```bash
make down MODE=docker
```

Dependency order:

`vault -> gitea -> gitlab -> nexus -> api -> jenkins -> nginx -> ollama -> chatbot`

Vault-dependent services (`gitea`, `gitlab`, `nexus`, `jenkins`) verify Vault health during startup and will reuse the current `MODE`.

## Cleanup

Remove generated service state from the services that persist local artifacts:

```bash
make distclean
# alias
make distclan
```

That cleanup currently runs `distclean` for `chatbot`, `ollama`, `nginx`, `jenkins`, `api`, `nexus`, `gitlab`, `gitea`, and `vault`.

## Central Port Configuration

Host-facing ports are managed centrally in:

`ports.env`

Update that file to change ports for all services in one place.
