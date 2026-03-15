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
- `jenkins`: Dual Jenkins setup (`prod` and `dev`) with preconfigured agents and pipeline bootstrap. <BR>
See [jenkins/README.md](jenkins/README.md).

## Top-level orchestration

A top-level `Makefile` can orchestrate all services.

Start all services in dependency order:

```bash
make all MODE=docker
```

Stop all services in reverse dependency order:

```bash
make down MODE=docker
```

Dependency order:

`vault -> gitea -> gitlab -> nexus -> api -> jenkins`

Vault-dependent services (`gitea`, `gitlab`, `nexus`, `jenkins`) verify Vault health during startup and will reuse the current `MODE`.

## Cleanup

Remove generated service state from the services that persist local artifacts:

```bash
make distclean
# alias
make distclan
```

That cleanup currently runs `distclean` for `jenkins`, `api`, `nexus`, `gitlab`, `gitea`, and `vault`.

## Central Port Configuration

Host-facing ports are managed centrally in:

`ports.env`

Update that file to change ports for all services in one place.
