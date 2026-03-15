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
VAULT_ADDR_RESOLVED="$(resolve_vault_addr bare)"
VAULT_TOKEN_RESOLVED="$(resolve_vault_token)"
export VAULT_ADDR="$VAULT_ADDR_RESOLVED"
export VAULT_TOKEN="$VAULT_TOKEN_RESOLVED"
export NEXUS_PYPI_REPO="${NEXUS_PYPI_REPO:-pypi-public}"

CURL_AUTH_ARGS=()
if [[ -n "${JENKINS_ADMIN_USER:-}" && -n "${JENKINS_ADMIN_PASSWORD:-}" ]]; then
  CURL_AUTH_ARGS=(-u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}")
fi

start_controller() {
  local instance="$1"
  local name branch port base_url root_url home_dir logs_dir pid_file log_file repo_url git_credentials_id git_username git_password
  local generate_library_repo_url generate_library_branch generate_library_source_repo_url generate_library_source_branch
  local library_example_client_repo_url library_example_client_branch library_example_client_source_repo_url library_example_client_source_branch
  local add_employee_repo_url add_employee_branch add_employee_source_repo_url add_employee_source_branch
  local add_employee_fastapi_roles_url add_employee_graphql_url

  name="$(instance_name "$instance")"
  branch="$(instance_branch "$instance")"
  repo_url="$(resolve_instance_pipeline_repo_url bare "$instance")"
  git_credentials_id="$(resolve_instance_pipeline_git_credentials_id bare "$instance")"
  git_username="$(resolve_instance_pipeline_git_username bare "$instance")"
  git_password="$(resolve_instance_pipeline_git_password bare "$instance")"
  generate_library_repo_url="$(resolve_instance_generate_library_pipeline_repo_url bare "$instance")"
  generate_library_branch="$(resolve_instance_generate_library_pipeline_branch "$instance")"
  generate_library_source_repo_url="$(resolve_instance_generate_library_source_repo_url "$instance")"
  generate_library_source_branch="$(resolve_instance_generate_library_source_branch "$instance")"
  library_example_client_repo_url="$(resolve_instance_library_example_client_pipeline_repo_url bare "$instance")"
  library_example_client_branch="$(resolve_instance_library_example_client_pipeline_branch "$instance")"
  library_example_client_source_repo_url="$(resolve_instance_library_example_client_source_repo_url "$instance")"
  library_example_client_source_branch="$(resolve_instance_library_example_client_source_branch "$instance")"
  add_employee_repo_url="$(resolve_instance_add_employee_pipeline_repo_url bare "$instance")"
  add_employee_branch="$(resolve_instance_add_employee_pipeline_branch "$instance")"
  add_employee_source_repo_url="$(resolve_instance_add_employee_source_repo_url "$instance")"
  add_employee_source_branch="$(resolve_instance_add_employee_source_branch "$instance")"
  add_employee_fastapi_roles_url="$(resolve_instance_add_employee_fastapi_roles_url bare "$instance")"
  add_employee_graphql_url="$(resolve_instance_add_employee_graphql_url "$instance")"
  port="$(instance_http_port "$instance")"
  base_url="$(instance_base_url "$instance")"
  root_url="$(resolve_instance_root_url "$instance")"
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
    export JENKINS_ROOT_URL="$root_url"
    export PIPELINE_REPO_URL="$repo_url"
    export PIPELINE_GIT_CREDENTIALS_ID="$git_credentials_id"
    export PIPELINE_GIT_USERNAME="$git_username"
    export PIPELINE_GIT_PASSWORD="$git_password"
    export PIPELINE_BRANCH="$branch"
    export GENERATE_LIBRARY_PIPELINE_REPO_URL="$generate_library_repo_url"
    export GENERATE_LIBRARY_PIPELINE_BRANCH="$generate_library_branch"
    export GENERATE_LIBRARY_SOURCE_REPO_URL="$generate_library_source_repo_url"
    export GENERATE_LIBRARY_SOURCE_BRANCH="$generate_library_source_branch"
    export LIBRARY_EXAMPLE_CLIENT_PIPELINE_REPO_URL="$library_example_client_repo_url"
    export LIBRARY_EXAMPLE_CLIENT_PIPELINE_BRANCH="$library_example_client_branch"
    export LIBRARY_EXAMPLE_CLIENT_SOURCE_REPO_URL="$library_example_client_source_repo_url"
    export LIBRARY_EXAMPLE_CLIENT_SOURCE_BRANCH="$library_example_client_source_branch"
    export ADD_EMPLOYEE_PIPELINE_REPO_URL="$add_employee_repo_url"
    export ADD_EMPLOYEE_PIPELINE_BRANCH="$add_employee_branch"
    export ADD_EMPLOYEE_SOURCE_REPO_URL="$add_employee_source_repo_url"
    export ADD_EMPLOYEE_SOURCE_BRANCH="$add_employee_source_branch"
    export ADD_EMPLOYEE_FASTAPI_ROLES_URL="$add_employee_fastapi_roles_url"
    export ADD_EMPLOYEE_GRAPHQL_URL="$add_employee_graphql_url"
    export PIPELINE_SCRIPT_PATH="$PIPELINE_SCRIPT_PATH"
    export PIPELINE_JOB_NAME="$PIPELINE_JOB_NAME"
    export PIPELINE_AUTH_TOKEN="$PIPELINE_AUTH_TOKEN"
    export PIPELINE_AUTO_TRIGGER="$PIPELINE_AUTO_TRIGGER"
    export GENERATE_LIBRARY_PIPELINE_AUTO_TRIGGER="$GENERATE_LIBRARY_PIPELINE_AUTO_TRIGGER"
    export LIBRARY_EXAMPLE_CLIENT_PIPELINE_JOB_NAME="$LIBRARY_EXAMPLE_CLIENT_PIPELINE_JOB_NAME"
    export LIBRARY_EXAMPLE_CLIENT_PIPELINE_AUTH_TOKEN="$LIBRARY_EXAMPLE_CLIENT_PIPELINE_AUTH_TOKEN"
    export LIBRARY_EXAMPLE_CLIENT_PIPELINE_AUTO_TRIGGER="$LIBRARY_EXAMPLE_CLIENT_PIPELINE_AUTO_TRIGGER"
    export ADD_EMPLOYEE_PIPELINE_JOB_NAME="$ADD_EMPLOYEE_PIPELINE_JOB_NAME"
    export ADD_EMPLOYEE_PIPELINE_AUTH_TOKEN="$ADD_EMPLOYEE_PIPELINE_AUTH_TOKEN"
    export ADD_EMPLOYEE_PIPELINE_AUTO_TRIGGER="$ADD_EMPLOYEE_PIPELINE_AUTO_TRIGGER"
    export AGENT_COUNT="$AGENT_COUNT"
    export AGENT_EXECUTORS="$AGENT_EXECUTORS"
    export JENKINS_ADMIN_USER="$JENKINS_ADMIN_USER"
    export JENKINS_ADMIN_PASSWORD="$JENKINS_ADMIN_PASSWORD"
    export JENKINS_REGULAR_USER="$JENKINS_REGULAR_USER"
    export JENKINS_REGULAR_PASSWORD="$JENKINS_REGULAR_PASSWORD"
    export JENKINS_CSP="$JENKINS_CSP"
    export TZ="$JENKINS_TIMEZONE"
    export VAULT_ADDR="$VAULT_ADDR"
    export VAULT_TOKEN="$VAULT_TOKEN"
    export NEXUS_PYPI_REPO="$NEXUS_PYPI_REPO"

    nohup "$JAVA_BIN" \
      -Djenkins.install.runSetupWizard=false \
      -Duser.timezone="$JENKINS_TIMEZONE" \
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
  TZ="$JENKINS_TIMEZONE" nohup "$JAVA_BIN" -Duser.timezone="$JENKINS_TIMEZONE" -jar "$agent_jar" \
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
