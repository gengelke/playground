> [!WARNING]
> This service is an experimental setup for educational purposes only.
> Do not expose it to the public internet.
> It uses convenience defaults that are acceptable only for isolated local testing.

> [!IMPORTANT]
> Parts of this service were generated with AI assistance.
> Review generated code and configuration carefully before using or modifying it.

# Zammad Playground Service

This service adds a local [Zammad](https://zammad.org) helpdesk stack to the
playground using Docker Compose. It follows the same repository conventions as
the other services:

- `make up MODE=docker` starts the service
- `make down MODE=docker` stops it
- `make status MODE=docker` shows container status
- `make logs MODE=docker` tails logs
- `make distclean` removes containers, volumes, and the generated `.env`

`MODE=bare` aliases the Docker workflow for this service.

## What gets generated

On the first `make up`, the bootstrap script:

- copies `.env.example` to `.env` if needed
- generates missing secrets for PostgreSQL, Elasticsearch, and the Zammad admin
- builds an `AUTOWIZARD_JSON` payload for first-run setup
- starts the official-style Zammad multi-container stack
- calls the autowizard endpoint to create the initial admin user
- syncs the resulting credentials to Vault path `secret/data/services/zammad`

## Vault secret shape

The service stores these fields in Vault:

- `url`
- `admin_user`
- `admin_password`
- `admin_firstname`
- `admin_lastname`
- `organization`
- `autowizard_token`
- `postgres_db`
- `postgres_user`
- `postgres_password`
- `elasticsearch_user`
- `elasticsearch_password`

## Usage

```bash
cd zammad
make up MODE=docker
```

Then open:

```text
http://127.0.0.1:8090
```

The actual host port follows `ZAMMAD_PORT` in `../ports.env`.

To inspect the synced Vault secret after startup:

```bash
cd ../vault
set -a
source .vault/credentials.env
set +a
curl -sS -H "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
  "${VAULT_ADDR}/v1/secret/data/services/zammad"
```

## Prerequisites

Zammad’s official Docker deployment expects meaningful local resources:

- Docker Compose available
- roughly 4 GB RAM available for the stack
- Elasticsearch host support for `vm.max_map_count=262144` on Linux hosts

If Elasticsearch fails to start on Linux, run:

```bash
sudo sysctl -w vm.max_map_count=262144
```

## Files

- `Makefile`: service lifecycle commands
- `docker-compose.yml`: Zammad stack
- `.env.example`: local defaults and generated secret placeholders
- `scripts/bootstrap.sh`: first-run bootstrap, autowizard execution, Vault sync
