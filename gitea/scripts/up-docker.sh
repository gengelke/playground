#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_cmd docker
require_cmd curl

compose_file="${ROOT_DIR}/docker-compose.yml"
docker_runtime="${ROOT_DIR}/runtime/docker"
gitea_config="${docker_runtime}/config/app.ini"

mkdir -p "${docker_runtime}/config" "${docker_runtime}/gitea" "${docker_runtime}/runner1" "${docker_runtime}/runner2"

prepare_bootstrap_env

"${ROOT_DIR}/scripts/render-gitea-config.sh" docker "$gitea_config"

log "Starting Gitea (docker mode)"
docker compose -f "$compose_file" up -d gitea

gitea_http_port="${GITEA_HTTP_PORT:-3000}"
wait_http "http://127.0.0.1:${gitea_http_port}/api/healthz" 180

admin_user="${GITEA_ADMIN_USER:-admin}"
admin_password="${GITEA_ADMIN_PASSWORD:-password}"
admin_email="${GITEA_ADMIN_EMAIL:-admin@example.com}"
user_name="${GITEA_USER:-myuser}"
user_password="${GITEA_USER_PASSWORD:-password}"
user_email="${GITEA_USER_EMAIL:-myuser@example.com}"

log "Ensuring admin user '${admin_user}' exists"
ensure_user_exists \
  docker compose -f "$compose_file" exec -T --user git gitea \
  gitea --config /data/gitea/conf/app.ini admin user create \
  --username "$admin_user" \
  --password "$admin_password" \
  --email "$admin_email" \
  --admin \
  --must-change-password=false

log "Setting admin password for '${admin_user}'"
docker compose -f "$compose_file" exec -T --user git gitea \
  gitea --config /data/gitea/conf/app.ini admin user change-password \
  --username "$admin_user" \
  --password "$admin_password" \
  --must-change-password=false

log "Ensuring user '${user_name}' exists"
ensure_user_exists \
  docker compose -f "$compose_file" exec -T --user git gitea \
  gitea --config /data/gitea/conf/app.ini admin user create \
  --username "$user_name" \
  --password "$user_password" \
  --email "$user_email" \
  --must-change-password=false

log "Setting password for user '${user_name}'"
docker compose -f "$compose_file" exec -T --user git gitea \
  gitea --config /data/gitea/conf/app.ini admin user change-password \
  --username "$user_name" \
  --password "$user_password" \
  --must-change-password=false

ensure_example_workflow_repo
ensure_jenkins_example_repo

log "Starting runner1 and runner2 (docker mode)"
docker compose -f "$compose_file" up -d runner1 runner2

log "Docker mode ready at http://localhost:${gitea_http_port}"
