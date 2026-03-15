<img width="1536" height="1024" alt="playground" src="https://github.com/user-attachments/assets/cb0e795a-50a6-44a5-b872-24ad7eecbd54" />
<br><br>

<h4><p align="center">This repository is for educational purposes. It contains playground setups for various tools & topics</p></h4>

## Services

- `vault`: Local HashiCorp Vault OSS environment with automatic bootstrap/init in docker or bare mode. See [vault/README.md](vault/README.md).
- `gitea`: Local Gitea SCM instance with two action runners, available in docker or bare mode. See [gitea/README.md](gitea/README.md).
- `gitlab`: Local GitLab CE setup with two GitLab Runner workers in docker or bare mode. See [gitlab/README.md](gitlab/README.md).
- `nexus`: Local Sonatype Nexus OSS repository manager with automated first-run initialization. See [nexus/README.md](nexus/README.md).
- `api`: FastAPI playground exposing REST and GraphQL endpoints, including client code generation/testing workflows. See [api/README.md](api/README.md).
- `jenkins`: Dual Jenkins setup (`prod` and `dev`) with preconfigured agents and pipeline bootstrap. See [jenkins/README.md](jenkins/README.md).
- `nginx`: Local reverse proxy for friendly service hostnames like `http://jenkins-dev`. See [nginx/README.md](nginx/README.md).

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

`vault -> gitea -> gitlab -> nexus -> api -> jenkins -> nginx`

Vault-dependent services (`gitea`, `gitlab`, `nexus`, `jenkins`) verify Vault health during startup and will reuse the current `MODE`.

## Cleanup

Remove generated service state from the services that persist local artifacts:

```bash
make distclean
# alias
make distclan
```

That cleanup currently runs `distclean` for `nginx`, `jenkins`, `api`, `nexus`, `gitlab`, `gitea`, and `vault`. `nginx` participates for consistency, but does not keep local generated state, so its cleanup is effectively a no-op.

## Central Port Configuration

Host-facing ports are managed centrally in:

`ports.env`

Update that file to change ports for all services in one place.

## Friendly service URLs (Docker mode)

Start everything:

```bash
make up MODE=docker
```

Add this to `/etc/hosts`:

```txt
127.0.0.1 jenkins-dev jenkins-prod api-dev gitea-dev gitlab-dev nexus-dev vault-dev
```

Then open:

- `http://jenkins-dev`
- `http://jenkins-prod`
- `http://api-dev`
- `http://gitea-dev`
- `http://gitlab-dev`
- `http://nexus-dev`
- `http://vault-dev`
