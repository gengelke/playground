# Local Nginx Reverse Proxy

This service exposes local playground services on friendly hostnames instead of `127.0.0.1:<port>`.

## Usage

```bash
make up MODE=docker
make status MODE=docker
```

Stop:

```bash
make down MODE=docker
```

`MODE=bare` is intentionally a no-op for this service.

If `NGINX_HTTP_PORT=80`, startup now fails fast when Rancher Desktop Kubernetes Traefik (`svclb-traefik`) is already bound to host port `80`.

## Hostnames

Add these entries to `/etc/hosts`:

```txt
127.0.0.1 jenkins-dev jenkins-prod api-dev gitea-dev gitlab-dev nexus-dev vault-dev
```

Then use:

- `http://jenkins-dev` -> Jenkins dev
- `http://jenkins-prod` -> Jenkins prod
- `http://api-dev` -> FastAPI
- `http://gitea-dev` -> Gitea
- `http://gitlab-dev` -> GitLab
- `http://nexus-dev` -> Nexus
- `http://vault-dev` -> Vault

## Config Overrides

You can override hostnames and upstream ports through environment variables:

- `NGINX_HTTP_PORT` (default `80`)
- `JENKINS_DEV_HOST`, `JENKINS_DEV_PORT`
- `JENKINS_PROD_HOST`, `JENKINS_PROD_PORT`
- `API_HOST`, `API_PORT`
- `GITEA_HOST`, `GITEA_PORT`
- `GITLAB_HOST`, `GITLAB_PORT`
- `NEXUS_HOST`, `NEXUS_PORT`
- `VAULT_HOST`, `VAULT_PORT`

Port values are centrally managed in `../ports.env` and reused across services.
