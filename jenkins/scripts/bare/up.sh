#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/env.sh
source "${SCRIPT_DIR}/../lib/env.sh"

ensure_admin_credentials
print_admin_credentials
PROD_PIPELINE_REPO_URL="$(resolve_instance_pipeline_repo_url bare prod)"
DEV_PIPELINE_REPO_URL="$(resolve_instance_pipeline_repo_url bare dev)"
PROD_PIPELINE_GIT_CREDENTIALS_ID="$(resolve_instance_pipeline_git_credentials_id bare prod)"
DEV_PIPELINE_GIT_CREDENTIALS_ID="$(resolve_instance_pipeline_git_credentials_id bare dev)"
print_pipeline_configuration "$PROD_PIPELINE_REPO_URL" "$DEV_PIPELINE_REPO_URL" "$PROD_PIPELINE_GIT_CREDENTIALS_ID" "$DEV_PIPELINE_GIT_CREDENTIALS_ID"

CURL_AUTH_ARGS=()
if [[ -n "${JENKINS_ADMIN_USER:-}" && -n "${JENKINS_ADMIN_PASSWORD:-}" ]]; then
  CURL_AUTH_ARGS=(-u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}")
fi

start_controller() {
  local instance="$1"
  local name branch port base_url home_dir logs_dir pid_file log_file repo_url git_credentials_id git_username git_password

  name="$(instance_name "$instance")"
  branch="$(instance_branch "$instance")"
  repo_url="$(resolve_instance_pipeline_repo_url bare "$instance")"
  git_credentials_id="$(resolve_instance_pipeline_git_credentials_id bare "$instance")"
  git_username="$(resolve_instance_pipeline_git_username bare "$instance")"
  git_password="$(resolve_instance_pipeline_git_password bare "$instance")"
  port="$(instance_http_port "$instance")"
  base_url="$(instance_base_url "$instance")"
  home_dir="$(instance_home "$instance")"
  logs_dir="$(instance_logs_dir "$instance")"
  pid_file="$(instance_controller_pid_file "$instance")"
  log_file="${logs_dir}/controller.log"

  mkdir -p "$logs_dir"

  if is_pid_running "$pid_file"; then
    echo "${name} already running"
    return
  fi

  echo "Starting ${name} on ${base_url}"
  (
    export JENKINS_HOME="$home_dir"
    export JENKINS_INSTANCE_NAME="$name"
    export PIPELINE_REPO_URL="$repo_url"
    export PIPELINE_GIT_CREDENTIALS_ID="$git_credentials_id"
    export PIPELINE_GIT_USERNAME="$git_username"
    export PIPELINE_GIT_PASSWORD="$git_password"
    export PIPELINE_BRANCH="$branch"
    export PIPELINE_SCRIPT_PATH="$PIPELINE_SCRIPT_PATH"
    export PIPELINE_JOB_NAME="$PIPELINE_JOB_NAME"
    export PIPELINE_AUTH_TOKEN="$PIPELINE_AUTH_TOKEN"
    export AGENT_COUNT="$AGENT_COUNT"
    export AGENT_EXECUTORS="$AGENT_EXECUTORS"
    export JENKINS_ADMIN_USER="$JENKINS_ADMIN_USER"
    export JENKINS_ADMIN_PASSWORD="$JENKINS_ADMIN_PASSWORD"
    export JENKINS_REGULAR_USER="$JENKINS_REGULAR_USER"
    export JENKINS_REGULAR_PASSWORD="$JENKINS_REGULAR_PASSWORD"

    nohup "$JAVA_BIN" \
      -Djenkins.install.runSetupWizard=false \
      -jar "$JENKINS_WAR_PATH" \
      --httpPort="$port" \
      --httpListenAddress=127.0.0.1 \
      >"$log_file" 2>&1 &

    echo $! >"$pid_file"
  )
}

wait_for_controller() {
  local instance="$1"
  local base_url timeout elapsed

  base_url="$(instance_base_url "$instance")"
  timeout="${CONTROLLER_START_TIMEOUT_SECONDS:-240}"
  elapsed=0

  until "$CURL_BIN" -fsSL "${CURL_AUTH_ARGS[@]}" "${base_url}login" >/dev/null 2>&1; do
    sleep 2
    elapsed=$((elapsed + 2))
    if (( elapsed >= timeout )); then
      echo "Timeout waiting for ${instance} controller (${base_url})" >&2
      exit 1
    fi
  done

  echo "${instance} controller is ready"
}

ensure_agent_jar() {
  local instance="$1"
  local base_url agent_jar

  base_url="$(instance_base_url "$instance")"
  agent_jar="${CACHE_DIR}/${instance}-agent.jar"

  "$CURL_BIN" -fsSL "${CURL_AUTH_ARGS[@]}" "${base_url}jnlpJars/agent.jar" -o "$agent_jar"
  printf '%s' "$agent_jar"
}

fetch_agent_secret() {
  local instance="$1"
  local index="$2"
  local node_name base_url jnlp_url xml secret retries max_retries

  node_name="$(agent_name "$instance" "$index")"
  base_url="$(instance_base_url "$instance")"
  jnlp_url="${base_url}computer/${node_name}/jenkins-agent.jnlp"

  max_retries="${AGENT_SECRET_MAX_RETRIES:-120}"
  retries=0

  while (( retries < max_retries )); do
    xml="$($CURL_BIN -fsSL "${CURL_AUTH_ARGS[@]}" "$jnlp_url" || true)"
    secret="$(printf '%s' "$xml" | grep -o '<argument>[^<]*</argument>' | sed -n '1{s#<argument>##;s#</argument>##;p;}' || true)"

    if [[ -n "$secret" ]]; then
      printf '%s' "$secret"
      return
    fi

    retries=$((retries + 1))
    sleep 2
  done

  echo "Could not fetch secret for ${node_name}" >&2
  return 1
}

start_agent() {
  local instance="$1"
  local index="$2"
  local node_name pid_file agent_dir work_dir logs_dir log_file agent_jar secret base_url

  node_name="$(agent_name "$instance" "$index")"
  pid_file="$(agent_pid_file "$instance" "$index")"
  agent_dir="$(agent_dir "$instance" "$index")"
  work_dir="${agent_dir}/work"
  logs_dir="$(instance_logs_dir "$instance")"
  log_file="${logs_dir}/${node_name}.log"
  base_url="$(instance_base_url "$instance")"

  mkdir -p "$work_dir" "$logs_dir"

  if is_pid_running "$pid_file"; then
    echo "${node_name} already running"
    return
  fi

  agent_jar="$(ensure_agent_jar "$instance")"
  secret="$(fetch_agent_secret "$instance" "$index")"

  echo "Starting ${node_name}"
  nohup "$JAVA_BIN" -jar "$agent_jar" \
    -url "$base_url" \
    -name "$node_name" \
    -secret "$secret" \
    -workDir "$work_dir" \
    -webSocket \
    >"$log_file" 2>&1 &

  echo $! >"$pid_file"
}

for instance in prod dev; do
  start_controller "$instance"
done

for instance in prod dev; do
  wait_for_controller "$instance"
done

for instance in prod dev; do
  for ((index=1; index<=AGENT_COUNT; index++)); do
    start_agent "$instance" "$index"
  done
done

bash "${SCRIPT_DIR}/../sync-regular-user-api-tokens.sh"

echo "All bare Jenkins controllers and agents are running"
print_instance_urls
