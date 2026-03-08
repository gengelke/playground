# Nexus OSS Setup (Makefile Managed)

This project supports two run modes through a single Makefile entrypoint:

- `make up MODE=docker` to run Nexus OSS in Docker
- `make up MODE=bare` to run Nexus OSS directly on the host

`make up` also performs first-run initialization automatically:

- waits until Nexus is healthy
- ensures a managed admin account and regular account exist
- configures anonymous access
- prints login credentials to the CLI

## Prerequisites

### Docker mode
- Docker Desktop (or Docker Engine + Compose plugin)

### Bare mode
- Java 17+ available on `PATH`
- `curl` and `tar`

## Usage

Start:

```bash
make up MODE=docker
make up MODE=bare
make up MODE=docker NEXUS_HTTP_PORT=18081
make up MODE=docker NEXUS_HTTP_PORT=18081 NEXUS_ADMIN_PASSWORD='MyStrongPass123!'
```

Stop:

```bash
make down MODE=docker
make down MODE=bare
```

Other:

```bash
make logs MODE=docker
make logs MODE=bare
make status MODE=docker
make status MODE=bare
make restart MODE=docker
make restart MODE=bare
```

By default Nexus is exposed at:

- `http://localhost:8083`

If `8083` is already used, choose another host port:

- `make up MODE=docker NEXUS_HTTP_PORT=18081`
- then open `http://localhost:18081`

Docker mode also auto-resolves port conflicts:

- `make up MODE=docker` first tries `8083`
- if `8083` is occupied, it picks the next free port automatically
- chosen port is printed in CLI and stored in `run/docker.port`

## Zero-Manual Initialization

By default (`NEXUS_AUTO_INIT=true`), `make up` performs initialization end-to-end.

- Default managed users:
  - admin user: `admin` / `password` (role `nx-admin`)
  - regular user: `user` / `password` (role `nx-anonymous`)
- Bootstrap still uses the built-in `admin` user behind the scenes and persists its password in `.nexus-admin-password`.
- You can disable all bootstrap automation with `NEXUS_AUTO_INIT=false`
- Bootstrap prints progress while waiting for Nexus readiness and admin auth
- If `../vault/.vault/credentials.env` is available and Vault is reachable, Nexus credentials are also synced to `secret/data/services/nexus`

## Configurable Variables

You can override any variable inline:

```bash
make up MODE=bare NEXUS_VERSION=3.70.1-02
```

Key vars:

- `NEXUS_VERSION` (default `3.70.1-02`)
- `NEXUS_DIST_URL` (auto-derived from version)
- `NEXUS_BASE_DIR` (default `.local`)
- `NEXUS_DATA_DIR` (default `data/bare-data`)
- `NEXUS_LOG_FILE` (default `logs/bare/nexus.log`)
- `NEXUS_PID_FILE` (default `run/nexus.pid`)
- `NEXUS_HTTP_PORT` (host/bare port, default `8083`)
- `NEXUS_BOOTSTRAP_USER` (default `admin`)
- `NEXUS_BOOTSTRAP_PASSWORD` (default empty -> `NEXUS_ADMIN_PASSWORD`)
- `NEXUS_ADMIN_USER` (default `admin`)
- `NEXUS_ADMIN_PASSWORD` (default `password`)
- `NEXUS_REGULAR_USER` (default `user`)
- `NEXUS_REGULAR_PASSWORD` (default `password`)
- `NEXUS_ANONYMOUS_ENABLED` (`true` or `false`, default `false`)
- `NEXUS_AUTO_INIT` (`true` or `false`, default `true`)
- `NEXUS_WAIT_TIMEOUT` (seconds, default `600`)
- `NEXUS_WAIT_INTERVAL` (seconds, default `5`)
- `NEXUS_CONNECT_TIMEOUT` (seconds per connection attempt, default `2`)
- `NEXUS_CURL_MAX_TIME` (seconds per HTTP call, default `5`)
- `NEXUS_DOCKER_PORT_FILE` (default `run/docker.port`)

## Data Locations

- Docker data: `data/docker-data`
- Bare data: `data/bare-data`
- Bare logs: `logs/bare/nexus.log`
