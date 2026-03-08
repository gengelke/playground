#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_cmd curl

prepare_bootstrap_env

gitea_bin="$(resolve_bin "${GITEA_BIN:-gitea}")"
runner_bin="$(resolve_bin "${ACT_RUNNER_BIN:-act_runner}")"

bare_runtime="${ROOT_DIR}/runtime/bare"
log_dir="${bare_runtime}/logs"
pid_dir="${bare_runtime}/pids"
config_dir="${bare_runtime}/config"
gitea_data_dir="${bare_runtime}/gitea"
repo_dir="${bare_runtime}/repositories"
runner1_dir="${bare_runtime}/runner1"
runner2_dir="${bare_runtime}/runner2"

mkdir -p "$log_dir" "$pid_dir" "$config_dir" "$gitea_data_dir" "$repo_dir" "$runner1_dir" "$runner2_dir"

gitea_config="${config_dir}/app.ini"
"${ROOT_DIR}/scripts/render-gitea-config.sh" bare "$gitea_config"

gitea_pid_file="${pid_dir}/gitea.pid"
if [[ -f "$gitea_pid_file" ]] && is_pid_running "$(cat "$gitea_pid_file" 2>/dev/null || true)"; then
  log "Gitea is already running (pid $(cat "$gitea_pid_file"))"
else
  log "Starting Gitea (bare mode)"
  nohup "$gitea_bin" web --config "$gitea_config" >"${log_dir}/gitea.log" 2>&1 &
  echo $! >"$gitea_pid_file"
fi

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
  "$gitea_bin" --config "$gitea_config" admin user create \
  --username "$admin_user" \
  --password "$admin_password" \
  --email "$admin_email" \
  --admin \
  --must-change-password=false

log "Setting admin password for '${admin_user}'"
"$gitea_bin" --config "$gitea_config" admin user change-password \
  --username "$admin_user" \
  --password "$admin_password" \
  --must-change-password=false

log "Ensuring user '${user_name}' exists"
ensure_user_exists \
  "$gitea_bin" --config "$gitea_config" admin user create \
  --username "$user_name" \
  --password "$user_password" \
  --email "$user_email" \
  --must-change-password=false

log "Setting password for user '${user_name}'"
"$gitea_bin" --config "$gitea_config" admin user change-password \
  --username "$user_name" \
  --password "$user_password" \
  --must-change-password=false

ensure_example_workflow_repo
ensure_jenkins_example_repo

runner_token="${GITEA_RUNNER_TOKEN:-local-runner-token-change-me}"
instance_url="http://127.0.0.1:${gitea_http_port}"
runner_labels="${RUNNER_LABELS_BARE:-linux-amd64:host}"

start_runner() {
  local runner_id="$1"
  local runner_name="$2"
  local runner_dir="$3"
  local runner_pid_file="${pid_dir}/${runner_id}.pid"

  if [[ -f "$runner_pid_file" ]] && is_pid_running "$(cat "$runner_pid_file" 2>/dev/null || true)"; then
    log "${runner_name} is already running (pid $(cat "$runner_pid_file"))"
    return 0
  fi

  if [[ ! -f "${runner_dir}/.runner" ]]; then
    log "Registering ${runner_name}"
    (
      cd "$runner_dir"
      "$runner_bin" register \
        --no-interactive \
        --instance "$instance_url" \
        --token "$runner_token" \
        --name "$runner_name" \
        --labels "$runner_labels"
    )
  fi

  log "Starting ${runner_name}"
  (
    cd "$runner_dir"
    nohup "$runner_bin" daemon >"${log_dir}/${runner_id}.log" 2>&1 &
    echo $! >"$runner_pid_file"
  )
}

start_runner "runner1" "${RUNNER1_NAME:-agent-runner-1}" "$runner1_dir"
start_runner "runner2" "${RUNNER2_NAME:-agent-runner-2}" "$runner2_dir"

log "Bare mode ready at http://localhost:${gitea_http_port}"
