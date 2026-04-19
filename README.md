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

The playground currently contains these top-level service components:

| Service | Make target | Description | Details |
| --- | --- | --- | --- |
| `vault` | `vault` | Local HashiCorp Vault OSS environment with automatic bootstrap/init in Docker or bare mode. | [vault/README.md](vault/README.md) |
| `gitea` | `gitea` | Local Gitea SCM instance with two action runners, available in Docker or bare mode. | [gitea/README.md](gitea/README.md) |
| `gitlab` | `gitlab` | Local GitLab CE setup with two GitLab Runner workers in Docker or bare mode. | [gitlab/README.md](gitlab/README.md) |
| `nexus` | `nexus` | Local Sonatype Nexus OSS repository manager with automated first-run initialization. | [nexus/README.md](nexus/README.md) |
| `api` | `api` | FastAPI playground exposing REST and GraphQL endpoints, including client code generation/testing workflows. | [api/README.md](api/README.md) |
| `jenkins` | `jenkins` | Dual Jenkins setup (`prod` and `dev`) with preconfigured agents and pipeline bootstrap. | [jenkins/README.md](jenkins/README.md) |
| `nginx` | `nginx` | Local HTTPS nginx service serving a static example page with the repository README image. | [nginx/README.md](nginx/README.md) |
| `ollama` | `ollama` | Local Ollama LLM runtime in Docker with persistent model storage and automatic `llama3.1` pull. | [ollama/README.md](ollama/README.md) |
| `chatbot` | `chatbot` | Local-first Python/FastAPI chatbot with CLI, REST API, web UI, configurable rules/tools/sources, SQLite document chunks, and optional Qdrant RAG. | [chatbot/README.md](chatbot/README.md) |

## Per-service usage

Each service has its own README and Makefile. Use the top-level Makefile for
common lifecycle commands. Replace `<service>` with one of:

```text
vault gitea gitlab nexus api jenkins nginx ollama chatbot
```

```bash
make up-<service> MODE=docker
make down-<service> MODE=docker
make status-<service> MODE=docker
make logs-<service> MODE=docker
```

Examples:

```bash
make up-vault MODE=docker
make status-gitlab MODE=docker
make logs-chatbot MODE=docker
make down-nginx MODE=docker
```

You can also work from inside a service directory:

```bash
cd chatbot
make up MODE=docker
```

For chatbot web UI, CLI, REST API, ingestion, RAG, and provider configuration,
see [chatbot/README.md](chatbot/README.md).

## Top-level orchestration

The top-level `Makefile` can orchestrate either every service or the smaller
DevOps scenario subset.

Start every service in dependency order:

```bash
make all MODE=docker
# same as
make up MODE=docker
```

Stop every service in reverse dependency order:

```bash
make down MODE=docker
```

All-service dependency order:

`vault -> gitea -> gitlab -> nexus -> api -> jenkins -> nginx -> ollama -> chatbot`

Start the DevOps scenario subset:

```bash
make devops MODE=docker
```

DevOps scenario order:

`vault -> nexus -> api -> gitea -> jenkins -> nginx -> ollama -> chatbot`

The DevOps scenario intentionally does not start `gitlab`; use `make all` or
`make up-gitlab` when you want GitLab as well. Vault-dependent services
(`gitea`, `gitlab`, `nexus`, `jenkins`) verify Vault health during startup and
reuse the current `MODE`.

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
