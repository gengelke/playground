# Vault OSS Local Setup

> [!WARNING]
> This service is an experimental setup for educational purposes only.
> Do not expose any part of it to the public internet.
> It uses insecure defaults such as default passwords and other convenience settings that are only acceptable for isolated local testing.

> [!IMPORTANT]
> Parts of this service were generated with AI assistance.
> Review generated code and configuration carefully before using or modifying this service.

Manage HashiCorp Vault (Open-Source Edition) with one Makefile:

- `make up MODE=docker` to run Vault in Docker
- `make up MODE=bare` to run Vault directly on your machine

## Requirements

- Docker mode: Docker + Docker Compose plugin
- Bare mode: `vault` binary installed and on `PATH`
- Optional for status checks: `curl`

## Commands

```bash
make help
make up MODE=docker
make up MODE=bare
make down MODE=docker
make down MODE=bare
make status MODE=docker
make logs MODE=bare
make restart MODE=docker
make creds
make clean
make distclean
```

## Vault Address

Both modes listen on:

```bash
export VAULT_ADDR=http://127.0.0.1:8200
```

## Automatic Initialization

`make up` automatically performs bootstrap when needed:

- waits for Vault API
- initializes Vault on first startup (`secret_shares=1`, `secret_threshold=1`)
- stores generated credentials in `./.vault/credentials.env`
- unseals Vault on startup
- ensures a `secret/` KV v2 mount exists for service credential sync
- enables `userpass` auth at `auth/userpass`
- configures default users:
  - `admin` / `password` (policy: `vault-admin`)
  - `user` / `password` (policy: `default`)
- prints `Root Token` and the login command in the CLI

After `make up`, you can login directly:

```bash
vault login <printed_root_token>
vault login -method=userpass username=admin password=password
vault login -method=userpass username=user password=password
```

You can print stored credentials anytime with:

```bash
make creds
```

## Files

- `Makefile`: unified lifecycle (`up/down/status/logs`)
- `docker-compose.yml`: Docker runtime
- `config/vault-docker.hcl`: Docker Vault config
- `config/vault-bare.hcl`: Bare Vault config
- `scripts/bootstrap-vault.sh`: auto init/unseal flow
- `scripts/kv-put.sh`: helper for other services to sync generated credentials into Vault KV
- `.vault/`: runtime data/logs/pid (gitignored)
- `make distclean`: same cleanup as `make clean`, removing `.vault/`
