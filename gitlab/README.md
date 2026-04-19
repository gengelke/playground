# GitLab CE setup (docker or bare) with 2 worker agents

> [!WARNING]
> This service is an experimental setup for educational purposes only.
> Do not expose any part of it to the public internet.
> It uses insecure defaults such as default passwords and other convenience settings that are only acceptable for isolated local testing.

> [!IMPORTANT]
> Parts of this service were generated with AI assistance.
> Review generated code and configuration carefully before using or modifying this service.

This repository provides a single Makefile entrypoint to run GitLab CE in two modes:

- `MODE=docker`: full stack in Docker (GitLab CE + 2 GitLab Runner workers)
- `MODE=bare`: install/start GitLab CE and GitLab Runner on host OS (Debian/Ubuntu style)

## Files

- `Makefile`: unified lifecycle commands
- `docker/docker-compose.yml`: Docker mode stack
- `docker/runner/register-runner.sh`: auto-register runner container and start worker process
- `bare/*.sh`: bare-mode install/lifecycle scripts
- `.env.example`: all configurable settings

## Quick start

1. Start stack:

```bash
make up MODE=docker
# or
make up MODE=bare
```

2. Login using credentials printed in the CLI output:

- Admin username: `admin`
- Admin password: `password` (or `GITLAB_ADMIN_PASSWORD`)
- Regular username: `user`
- Regular password: `password` (or `GITLAB_USER_PASSWORD`)

3. Check status:

```bash
make status MODE=docker
# or
make status MODE=bare
```

## Common commands

```bash
make up MODE=docker
make down MODE=docker
make logs MODE=docker
make distclean

make up MODE=bare
make down MODE=bare
make logs MODE=bare
```

## Notes

- Docker mode publishes GitLab web on `http://localhost:8929` (`GITLAB_HTTP_PORT`) and SSH on port `2224` (`GITLAB_SSH_PORT`) by default.
- Leave `RUNNER_GITLAB_URL` empty to use sane defaults (`http://gitlab:8929` for docker mode, `GITLAB_EXTERNAL_URL` for bare mode).
- Bare mode scripts assume Debian/Ubuntu package management and use `sudo` when needed.
- If `.env` does not exist, it is created automatically from `.env.example`.
- Setup auto-generates missing runner auth credentials and writes them to `.env`.
- On startup, scripts ensure managed login users exist and are synced: `admin/password` and `user/password` (override via `GITLAB_ADMIN_PASSWORD` and `GITLAB_USER_PASSWORD`).
- Generated credentials are printed to CLI so no manual bootstrap steps are required.
- If `../vault/.vault/credentials.env` is available and Vault is reachable, GitLab credentials are also synced to `secret/data/services/gitlab`.
- `make distclean` removes the generated `.env` file after stopping local services.
- If you only want runner registration without reinstalling GitLab in bare mode, set:

```bash
BARE_INSTALL_GITLAB=0
BARE_INSTALL_RUNNER=1
```

in `.env` and run `make up MODE=bare` again.
