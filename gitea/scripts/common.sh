#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() {
  printf "[%s] %s\n" "$(date +"%H:%M:%S")" "$*"
}

die() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

resolve_bin() {
  local bin="$1"
  if [[ "$bin" == */* ]]; then
    [[ -x "$bin" ]] || die "Binary is not executable: $bin"
    printf "%s" "$bin"
    return 0
  fi

  local resolved
  resolved="$(command -v "$bin" 2>/dev/null || true)"
  [[ -n "$resolved" ]] || die "Cannot find binary in PATH: $bin"
  printf "%s" "$resolved"
}

wait_http() {
  local url="$1"
  local timeout="${2:-120}"
  local sleep_s=2
  local elapsed=0

  while ((elapsed < timeout)); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$sleep_s"
    elapsed=$((elapsed + sleep_s))
  done

  die "Timed out waiting for $url"
}

is_pid_running() {
  local pid="${1:-}"
  [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1
}

stop_pid_file() {
  local pid_file="$1"
  local name="$2"

  if [[ ! -f "$pid_file" ]]; then
    return 0
  fi

  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if is_pid_running "$pid"; then
    log "Stopping ${name} (pid ${pid})"
    kill "$pid" >/dev/null 2>&1 || true

    local retries=10
    while is_pid_running "$pid" && ((retries > 0)); do
      sleep 1
      retries=$((retries - 1))
    done

    if is_pid_running "$pid"; then
      log "Force killing ${name} (pid ${pid})"
      kill -9 "$pid" >/dev/null 2>&1 || true
    fi
  fi

  rm -f "$pid_file"
}

ensure_user_exists() {
  local exists_pattern="already exists"
  local tmp_file
  tmp_file="$(mktemp)"

  set +e
  "$@" >"$tmp_file" 2>&1
  local rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    rm -f "$tmp_file"
    return 0
  fi

  if grep -qi "$exists_pattern" "$tmp_file"; then
    rm -f "$tmp_file"
    return 0
  fi

  cat "$tmp_file" >&2
  rm -f "$tmp_file"
  return "$rc"
}

# Backward-compatible alias.
ensure_admin_user() {
  ensure_user_exists "$@"
}

random_string() {
  local len="${1:-32}"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex $((len / 2 + 1)) | cut -c1-"$len"
    return 0
  fi

  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr -d '-' | cut -c1-"$len"
    return 0
  fi

  die "Cannot generate random credentials (need openssl or uuidgen)"
}

envfile_get() {
  local file="$1"
  local key="$2"
  [[ -f "$file" ]] || return 1
  local line
  line="$(grep -E "^${key}=" "$file" | tail -n1 || true)"
  [[ -n "$line" ]] || return 1
  printf "%s" "${line#*=}"
}

envfile_set() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp
  tmp="$(mktemp)"

  if [[ -f "$file" ]]; then
    grep -v -E "^${key}=" "$file" >"$tmp" || true
  fi
  printf "%s=%s\n" "$key" "$value" >>"$tmp"
  mv "$tmp" "$file"
}

json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

resolve_example_workflow_service_host() {
  case "${MODE:-docker}" in
    docker) printf '%s' "host.docker.internal" ;;
    *) printf '%s' "127.0.0.1" ;;
  esac
}

rewrite_service_url_for_host() {
  local url="$1"
  local host="$2"

  printf '%s' "$url" | sed \
    -e "s#http://localhost#http://${host}#g" \
    -e "s#http://127.0.0.1#http://${host}#g" \
    -e "s#https://localhost#https://${host}#g" \
    -e "s#https://127.0.0.1#https://${host}#g"
}

resolve_example_workflow_vault_addr() {
  local creds_file="${ROOT_DIR}/../vault/.vault/credentials.env"
  local host
  host="$(resolve_example_workflow_service_host)"
  local value="${VAULT_ADDR:-}"

  if [[ -z "$value" ]]; then
    value="$(envfile_get "$creds_file" "VAULT_ADDR" || true)"
  fi
  if [[ -z "$value" ]]; then
    value="http://127.0.0.1:8200"
  fi

  rewrite_service_url_for_host "$value" "$host"
}

resolve_example_workflow_vault_token() {
  local creds_file="${ROOT_DIR}/../vault/.vault/credentials.env"
  local value="${VAULT_TOKEN:-${VAULT_ROOT_TOKEN:-}}"

  if [[ -z "$value" ]]; then
    value="$(envfile_get "$creds_file" "VAULT_TOKEN" || true)"
  fi
  if [[ -z "$value" ]]; then
    value="$(envfile_get "$creds_file" "VAULT_ROOT_TOKEN" || true)"
  fi

  printf '%s' "$value"
}

resolve_example_workflow_graphql_url() {
  local host
  host="$(resolve_example_workflow_service_host)"
  local value="${GITEA_LIBRARY_EXAMPLE_CLIENT_WORKFLOW_GRAPHQL_URL:-}"

  if [[ -z "$value" ]]; then
    value="http://127.0.0.1:8000/graphql"
  fi

  rewrite_service_url_for_host "$value" "$host"
}

resolve_add_employee_workflow_graphql_url() {
  local host
  host="$(resolve_example_workflow_service_host)"
  local value="${GITEA_ADD_EMPLOYEE_WORKFLOW_GRAPHQL_URL:-}"

  if [[ -z "$value" ]]; then
    value="http://127.0.0.1:8000/graphql"
  fi

  rewrite_service_url_for_host "$value" "$host"
}

resolve_print_employee_workflow_graphql_url() {
  local host
  host="$(resolve_example_workflow_service_host)"
  local value="${GITEA_PRINT_EMPLOYEE_WORKFLOW_GRAPHQL_URL:-}"

  if [[ -z "$value" ]]; then
    value="http://127.0.0.1:8000/graphql"
  fi

  rewrite_service_url_for_host "$value" "$host"
}

resolve_local_gitea_repo_url_for_host() {
  local host="$1"
  local owner="${GITEA_USER:-myuser}"
  local repo_name="${GITEA_PLAYGROUND_SOURCE_REPO:-playground}"
  local gitea_http_port="${GITEA_HTTP_PORT:-3000}"
  local instance_url="${GITEA_ROOT_URL:-http://localhost:${gitea_http_port}/}"

  instance_url="${instance_url%/}"
  instance_url="$(rewrite_service_url_for_host "$instance_url" "$host")"
  printf '%s/%s/%s.git' "$instance_url" "$owner" "$repo_name"
}

resolve_local_playground_source_repo_url() {
  resolve_local_gitea_repo_url_for_host "$(resolve_example_workflow_service_host)"
}

ensure_repo_actions_secret() {
  local instance_url="$1"
  local owner="$2"
  local password="$3"
  local repo_name="$4"
  local secret_name="$5"
  local secret_value="$6"
  local description="$7"

  [[ -n "$secret_value" ]] || die "Cannot set empty Actions secret '${secret_name}' for '${owner}/${repo_name}'"

  local payload
  payload="$(printf '{"data":"%s","description":"%s"}' \
    "$(json_escape "$secret_value")" \
    "$(json_escape "$description")")"

  local body_file
  body_file="$(mktemp)"
  local status
  status="$(curl -sS -o "$body_file" -w '%{http_code}' \
    --user "${owner}:${password}" \
    -H 'Content-Type: application/json' \
    -X PUT \
    --data "$payload" \
    "${instance_url}/api/v1/repos/${owner}/${repo_name}/actions/secrets/${secret_name}" || true)"

  if [[ "$status" != "201" && "$status" != "204" ]]; then
    cat "$body_file" >&2 || true
    rm -f "$body_file"
    die "Failed to ensure Actions secret '${secret_name}' for '${owner}/${repo_name}' (HTTP ${status})"
  fi
  rm -f "$body_file"
}

ensure_repo_file_in_branch() {
  local instance_url="$1"
  local owner="$2"
  local password="$3"
  local repo_name="$4"
  local file_path="$5"
  local target_branch="$6"
  local commit_message="$7"
  local content="$8"

  local file_url="${instance_url}/api/v1/repos/${owner}/${repo_name}/contents/${file_path}"
  local content_b64
  content_b64="$(printf '%s' "$content" | base64 | tr -d '\n')"

  local get_body
  get_body="$(mktemp)"
  local get_status
  get_status="$(curl -sS -o "$get_body" -w '%{http_code}' \
    --user "${owner}:${password}" \
    "${file_url}?ref=${target_branch}" || true)"

  local existing_sha=""
  if [[ "$get_status" == "200" ]]; then
    existing_sha="$(tr -d '\n' <"$get_body" | sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  elif [[ "$get_status" != "404" ]]; then
    cat "$get_body" >&2 || true
    rm -f "$get_body"
    die "Failed to query ${file_path} in branch '${target_branch}' for '${owner}/${repo_name}' (HTTP ${get_status})"
  fi
  rm -f "$get_body"

  local payload
  local write_method
  if [[ -n "$existing_sha" ]]; then
    payload="$(printf '{"content":"%s","message":"%s","branch":"%s","sha":"%s"}' \
      "$content_b64" \
      "$(json_escape "$commit_message")" \
      "$target_branch" \
      "$existing_sha")"
    write_method="PUT"
  else
    payload="$(printf '{"content":"%s","message":"%s","branch":"%s"}' \
      "$content_b64" \
      "$(json_escape "$commit_message")" \
      "$target_branch")"
    write_method="POST"
  fi

  local write_body
  write_body="$(mktemp)"
  local write_status
  write_status="$(curl -sS -o "$write_body" -w '%{http_code}' \
    --user "${owner}:${password}" \
    -H 'Content-Type: application/json' \
    -X "$write_method" \
    --data "$payload" \
    "$file_url" || true)"

  if [[ "$write_status" != "200" && "$write_status" != "201" ]]; then
    cat "$write_body" >&2 || true
    rm -f "$write_body"
    die "Failed to ensure ${file_path} in branch '${target_branch}' for '${owner}/${repo_name}' (HTTP ${write_status})"
  fi
  rm -f "$write_body"
}

sync_credentials_to_vault() {
  local vault_helper="${ROOT_DIR}/../vault/scripts/kv-put.sh"
  local gitea_root_url="${GITEA_ROOT_URL:-http://localhost:${GITEA_HTTP_PORT:-3000}/}"

  if [[ ! -x "$vault_helper" ]]; then
    log "Vault sync skipped: helper script not found at ${vault_helper}"
    return 0
  fi

  if ! "$vault_helper" "services/gitea" \
    "mode" "${MODE:-unknown}" \
    "root_url" "$gitea_root_url" \
    "admin_user" "${GITEA_ADMIN_USER:-}" \
    "admin_email" "${GITEA_ADMIN_EMAIL:-}" \
    "admin_password" "${GITEA_ADMIN_PASSWORD:-}" \
    "user" "${GITEA_USER:-}" \
    "user_email" "${GITEA_USER_EMAIL:-}" \
    "user_password" "${GITEA_USER_PASSWORD:-}" \
    "runner_registration_token" "${GITEA_RUNNER_TOKEN:-}" \
    "secret_key" "${GITEA_SECRET_KEY:-}" \
    "internal_token" "${GITEA_INTERNAL_TOKEN:-}" \
    "jwt_secret" "${GITEA_JWT_SECRET:-}"; then
    log "Warning: failed to sync Gitea credentials to Vault."
  fi
}

prepare_bootstrap_env() {
  local shared_dir="${ROOT_DIR}/runtime/shared"
  local env_file="${shared_dir}/generated.env"
  mkdir -p "$shared_dir"
  touch "$env_file"

  local explicit_admin_password=0
  local explicit_user_password=0
  if [[ -n "${GITEA_ADMIN_PASSWORD:-}" ]]; then
    explicit_admin_password=1
  fi
  if [[ -n "${GITEA_USER_PASSWORD:-}" ]]; then
    explicit_user_password=1
  fi

  local from_file
  if [[ -z "${GITEA_ADMIN_USER:-}" ]]; then
    GITEA_ADMIN_USER="admin"
  fi
  if [[ -z "${GITEA_ADMIN_EMAIL:-}" ]]; then
    GITEA_ADMIN_EMAIL="admin@example.com"
  fi
  if [[ -z "${GITEA_ADMIN_PASSWORD:-}" ]]; then
    GITEA_ADMIN_PASSWORD="password"
  fi
  if [[ -z "${GITEA_USER:-}" ]]; then
    GITEA_USER="myuser"
  fi
  if [[ -z "${GITEA_USER_EMAIL:-}" ]]; then
    GITEA_USER_EMAIL="myuser@example.com"
  fi
  if [[ -z "${GITEA_USER_PASSWORD:-}" ]]; then
    GITEA_USER_PASSWORD="password"
  fi
  if [[ "${GITEA_USER}" == "user" ]]; then
    log "GITEA_USER='user' is reserved in this Gitea version; using 'myuser' instead."
    GITEA_USER="myuser"
    if [[ "${GITEA_USER_EMAIL}" == "user@example.com" ]]; then
      GITEA_USER_EMAIL="myuser@example.com"
    fi
  fi
  # Bootstrap with a non-default registration token; the authoritative token
  # used for runner registration is generated from Gitea after startup.
  GITEA_RUNNER_TOKEN="$(random_string 48)"
  if [[ -z "${GITEA_SECRET_KEY:-}" ]]; then
    from_file="$(envfile_get "$env_file" "GITEA_SECRET_KEY" || true)"
    if [[ -n "$from_file" ]]; then
      GITEA_SECRET_KEY="$from_file"
    else
      GITEA_SECRET_KEY="$(random_string 64)"
      envfile_set "$env_file" "GITEA_SECRET_KEY" "$GITEA_SECRET_KEY"
    fi
  fi
  if [[ -z "${GITEA_INTERNAL_TOKEN:-}" ]]; then
    from_file="$(envfile_get "$env_file" "GITEA_INTERNAL_TOKEN" || true)"
    if [[ -n "$from_file" ]]; then
      GITEA_INTERNAL_TOKEN="$from_file"
    else
      GITEA_INTERNAL_TOKEN="$(random_string 64)"
      envfile_set "$env_file" "GITEA_INTERNAL_TOKEN" "$GITEA_INTERNAL_TOKEN"
    fi
  fi
  if [[ -z "${GITEA_JWT_SECRET:-}" ]]; then
    from_file="$(envfile_get "$env_file" "GITEA_JWT_SECRET" || true)"
    if [[ -n "$from_file" ]]; then
      GITEA_JWT_SECRET="$from_file"
    else
      GITEA_JWT_SECRET="$(random_string 64)"
      envfile_set "$env_file" "GITEA_JWT_SECRET" "$GITEA_JWT_SECRET"
    fi
  fi

  envfile_set "$env_file" "GITEA_ADMIN_USER" "$GITEA_ADMIN_USER"
  envfile_set "$env_file" "GITEA_ADMIN_PASSWORD" "$GITEA_ADMIN_PASSWORD"
  envfile_set "$env_file" "GITEA_ADMIN_EMAIL" "$GITEA_ADMIN_EMAIL"
  envfile_set "$env_file" "GITEA_USER" "$GITEA_USER"
  envfile_set "$env_file" "GITEA_USER_PASSWORD" "$GITEA_USER_PASSWORD"
  envfile_set "$env_file" "GITEA_USER_EMAIL" "$GITEA_USER_EMAIL"

  export GITEA_ADMIN_USER
  export GITEA_ADMIN_EMAIL
  export GITEA_ADMIN_PASSWORD
  export GITEA_USER
  export GITEA_USER_EMAIL
  export GITEA_USER_PASSWORD
  export GITEA_SECRET_KEY
  export GITEA_INTERNAL_TOKEN
  export GITEA_JWT_SECRET

  if (( explicit_admin_password == 0 )); then
    log "Admin login username: ${GITEA_ADMIN_USER}"
    log "Admin login password: ${GITEA_ADMIN_PASSWORD}"
  fi
  if (( explicit_user_password == 0 )); then
    log "User login username: ${GITEA_USER}"
    log "User login password: ${GITEA_USER_PASSWORD}"
  fi
  if (( explicit_admin_password == 0 || explicit_user_password == 0 )); then
    log "Persisted bootstrap values in: ${env_file}"
  fi
}

ensure_standard_users() {
  local -a gitea_cli=("$@")

  local admin_user="${GITEA_ADMIN_USER:-admin}"
  local admin_password="${GITEA_ADMIN_PASSWORD:-password}"
  local admin_email="${GITEA_ADMIN_EMAIL:-admin@example.com}"
  local user_name="${GITEA_USER:-myuser}"
  local user_password="${GITEA_USER_PASSWORD:-password}"
  local user_email="${GITEA_USER_EMAIL:-myuser@example.com}"

  log "Ensuring admin user '${admin_user}' exists"
  ensure_user_exists \
    "${gitea_cli[@]}" admin user create \
    --username "$admin_user" \
    --password "$admin_password" \
    --email "$admin_email" \
    --admin \
    --must-change-password=false

  log "Setting admin password for '${admin_user}'"
  "${gitea_cli[@]}" admin user change-password \
    --username "$admin_user" \
    --password "$admin_password" \
    --must-change-password=false

  log "Ensuring user '${user_name}' exists"
  ensure_user_exists \
    "${gitea_cli[@]}" admin user create \
    --username "$user_name" \
    --password "$user_password" \
    --email "$user_email" \
    --must-change-password=false

  log "Setting password for user '${user_name}'"
  "${gitea_cli[@]}" admin user change-password \
    --username "$user_name" \
    --password "$user_password" \
    --must-change-password=false
}

generate_and_persist_runner_token() {
  local env_file="$1"
  shift
  local -a gitea_cli=("$@")

  local runner_token
  runner_token="$("${gitea_cli[@]}" actions generate-runner-token | tr -d '\r\n')"
  [[ -n "$runner_token" ]] || die "Failed to generate runner registration token from Gitea"

  GITEA_RUNNER_TOKEN="$runner_token"
  export GITEA_RUNNER_TOKEN
  envfile_set "$env_file" "GITEA_RUNNER_TOKEN" "$GITEA_RUNNER_TOKEN"
  sync_credentials_to_vault
  log "Generated and persisted runner registration token from Gitea."
}

ensure_bootstrap_repositories() {
  ensure_playground_source_repo
  remove_example_workflow_repo
  ensure_example_pipeline_repo
  ensure_example_pipeline_gitea_workflow
  ensure_generate_library_repo
  ensure_library_example_client_repo
  ensure_add_employee_repo
  ensure_print_employee_repo
}

ensure_playground_source_repo() {
  local auto_add="${GITEA_AUTO_ADD_PLAYGROUND_SOURCE_REPO:-true}"
  auto_add="$(printf '%s' "$auto_add" | tr '[:upper:]' '[:lower:]')"
  case "$auto_add" in
    1|true|yes|on) ;;
    *)
      log "Skipping playground source repo setup (GITEA_AUTO_ADD_PLAYGROUND_SOURCE_REPO=${GITEA_AUTO_ADD_PLAYGROUND_SOURCE_REPO:-false})"
      return 0
      ;;
  esac

  require_cmd git

  local source_dir="${ROOT_DIR}/.."
  local repo_name="${GITEA_PLAYGROUND_SOURCE_REPO:-playground}"
  local gitea_http_port="${GITEA_HTTP_PORT:-3000}"
  local instance_url="${GITEA_ROOT_URL:-http://localhost:${gitea_http_port}/}"
  local owner="${GITEA_USER:-myuser}"
  local password="${GITEA_USER_PASSWORD:-password}"
  local email="${GITEA_USER_EMAIL:-myuser@example.com}"

  instance_url="${instance_url%/}"

  local create_body
  create_body="$(mktemp)"
  local create_payload
  create_payload="$(printf '{"name":"%s","auto_init":false,"private":false}' "$repo_name")"
  local create_status
  create_status="$(curl -sS -o "$create_body" -w '%{http_code}' \
    --user "${owner}:${password}" \
    -H 'Content-Type: application/json' \
    -X POST \
    --data "$create_payload" \
    "${instance_url}/api/v1/user/repos" || true)"

  if [[ "$create_status" != "201" && "$create_status" != "409" ]]; then
    cat "$create_body" >&2 || true
    rm -f "$create_body"
    die "Failed to create playground source repository '${owner}/${repo_name}' (HTTP ${create_status})"
  fi
  rm -f "$create_body"

  local update_body
  update_body="$(mktemp)"
  local update_status
  update_status="$(curl -sS -o "$update_body" -w '%{http_code}' \
    --user "${owner}:${password}" \
    -H 'Content-Type: application/json' \
    -X PATCH \
    --data '{"private":false}' \
    "${instance_url}/api/v1/repos/${owner}/${repo_name}" || true)"

  if [[ "$update_status" != "200" ]]; then
    cat "$update_body" >&2 || true
    rm -f "$update_body"
    die "Failed to mark playground source repository '${owner}/${repo_name}' as public (HTTP ${update_status})"
  fi
  rm -f "$update_body"

  local sync_dir
  sync_dir="$(mktemp -d)"
  local auth_header
  auth_header="$(printf '%s:%s' "$owner" "$password" | base64 | tr -d '\n')"
  local remote_url="${instance_url}/${owner}/${repo_name}.git"

  (
    cd "$sync_dir"
    git init --initial-branch=main >/dev/null
    git config user.name "Gitea Bootstrap"
    git config user.email "$email"
  )

  while IFS= read -r -d '' relative_path; do
    mkdir -p "${sync_dir}/$(dirname "$relative_path")"
    cp -pP "${source_dir}/${relative_path}" "${sync_dir}/${relative_path}"
  done < <(git -C "$source_dir" ls-files -co --exclude-standard -z)

  (
    cd "$sync_dir"
    git add -A
    git commit -m "chore: sync local playground source snapshot" >/dev/null
    git branch dev
    git remote add origin "$remote_url"
    git -c "http.extraHeader=Authorization: Basic ${auth_header}" push --force origin main >/dev/null
    git -c "http.extraHeader=Authorization: Basic ${auth_header}" push --force origin dev >/dev/null
  )

  rm -rf "$sync_dir"
  log "Ensured public playground source repo '${owner}/${repo_name}' from local workspace"
}

ensure_example_pipeline_gitea_workflow() {
  local auto_add="${GITEA_AUTO_ADD_EXAMPLE_PIPELINE_WORKFLOW:-${GITEA_AUTO_ADD_EXAMPLE_WORKFLOW:-true}}"
  auto_add="$(printf '%s' "$auto_add" | tr '[:upper:]' '[:lower:]')"
  case "$auto_add" in
    1|true|yes|on) ;;
    *)
      log "Skipping example-pipeline workflow setup (GITEA_AUTO_ADD_EXAMPLE_PIPELINE_WORKFLOW=${GITEA_AUTO_ADD_EXAMPLE_PIPELINE_WORKFLOW:-false})"
      return 0
      ;;
  esac

  local gitea_http_port="${GITEA_HTTP_PORT:-3000}"
  local instance_url="${GITEA_ROOT_URL:-http://localhost:${gitea_http_port}/}"
  instance_url="${instance_url%/}"

  local owner="${GITEA_USER:-myuser}"
  local password="${GITEA_USER_PASSWORD:-password}"
  local repo_name="${GITEA_EXAMPLE_PIPELINE_REPO:-example-pipeline}"
  local file_path=".gitea/workflows/example-pipeline.yml"

  local repo_body
  repo_body="$(mktemp)"
  local repo_status
  repo_status="$(curl -sS -o "$repo_body" -w '%{http_code}' \
    --user "${owner}:${password}" \
    "${instance_url}/api/v1/repos/${owner}/${repo_name}" || true)"
  if [[ "$repo_status" != "200" ]]; then
    cat "$repo_body" >&2 || true
    rm -f "$repo_body"
    die "Failed to query repository metadata for '${owner}/${repo_name}' (HTTP ${repo_status})"
  fi

  local default_branch
  default_branch="$(tr -d '\n' <"$repo_body" | sed -n 's/.*"default_branch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  rm -f "$repo_body"
  if [[ -z "$default_branch" ]]; then
    default_branch="main"
  fi

  local workflow_content
  workflow_content="$(cat <<'EOF'
name: example-pipeline

on:
  push:
  workflow_dispatch:

jobs:
  hello:
    runs-on: linux-amd64
    steps:
      - name: Print hello world
        run: echo "Hello World"
EOF
)"

  ensure_repo_file_in_branch \
    "$instance_url" \
    "$owner" \
    "$password" \
    "$repo_name" \
    "$file_path" \
    "$default_branch" \
    "chore: sync example-pipeline gitea workflow" \
    "$workflow_content"
  ensure_repo_file_in_branch \
    "$instance_url" \
    "$owner" \
    "$password" \
    "$repo_name" \
    "$file_path" \
    "dev" \
    "chore: sync example-pipeline gitea workflow" \
    "$workflow_content"

  log "Ensured example-pipeline Gitea workflow in '${owner}/${repo_name}:${file_path}'"
}

remove_example_workflow_repo() {
  local remove_repo="${GITEA_REMOVE_EXAMPLE_WORKFLOW_REPO:-false}"
  remove_repo="$(printf '%s' "$remove_repo" | tr '[:upper:]' '[:lower:]')"
  case "$remove_repo" in
    1|true|yes|on) ;;
    *)
      log "Keeping example workflow repo (GITEA_REMOVE_EXAMPLE_WORKFLOW_REPO=${GITEA_REMOVE_EXAMPLE_WORKFLOW_REPO:-false})"
      return 0
      ;;
  esac

  local gitea_http_port="${GITEA_HTTP_PORT:-3000}"
  local instance_url="${GITEA_ROOT_URL:-http://localhost:${gitea_http_port}/}"
  instance_url="${instance_url%/}"

  local owner="${GITEA_USER:-myuser}"
  local password="${GITEA_USER_PASSWORD:-password}"
  local repo_name="actions-example"

  local delete_body
  delete_body="$(mktemp)"
  local delete_status
  delete_status="$(curl -sS -o "$delete_body" -w '%{http_code}' \
    --user "${owner}:${password}" \
    -X DELETE \
    "${instance_url}/api/v1/repos/${owner}/${repo_name}" || true)"

  if [[ "$delete_status" == "204" ]]; then
    log "Removed legacy example workflow repo '${owner}/${repo_name}'"
  elif [[ "$delete_status" == "404" ]]; then
    log "Legacy example workflow repo '${owner}/${repo_name}' is already absent"
  else
    cat "$delete_body" >&2 || true
    rm -f "$delete_body"
    die "Failed to remove legacy example workflow repo '${owner}/${repo_name}' (HTTP ${delete_status})"
  fi
  rm -f "$delete_body"
}

rename_legacy_generate_api_library_repo() {
  local gitea_http_port="${GITEA_HTTP_PORT:-3000}"
  local instance_url="${GITEA_ROOT_URL:-http://localhost:${gitea_http_port}/}"
  instance_url="${instance_url%/}"

  local owner="${GITEA_USER:-myuser}"
  local password="${GITEA_USER_PASSWORD:-password}"
  local old_repo="generate-api-library"
  local new_repo="${GITEA_GENERATE_LIBRARY_REPO:-generate-library}"

  if [[ "$old_repo" == "$new_repo" ]]; then
    return 0
  fi

  local old_status
  old_status="$(curl -sS -o /tmp/gitea-repo-old.out -w '%{http_code}' \
    --user "${owner}:${password}" \
    "${instance_url}/api/v1/repos/${owner}/${old_repo}" || true)"
  if [[ "$old_status" == "404" ]]; then
    rm -f /tmp/gitea-repo-old.out
    return 0
  fi
  if [[ "$old_status" != "200" ]]; then
    cat /tmp/gitea-repo-old.out >&2 || true
    rm -f /tmp/gitea-repo-old.out
    die "Failed to query legacy repo '${owner}/${old_repo}' (HTTP ${old_status})"
  fi
  rm -f /tmp/gitea-repo-old.out

  local new_status
  new_status="$(curl -sS -o /tmp/gitea-repo-new.out -w '%{http_code}' \
    --user "${owner}:${password}" \
    "${instance_url}/api/v1/repos/${owner}/${new_repo}" || true)"
  if [[ "$new_status" == "200" ]]; then
    rm -f /tmp/gitea-repo-new.out
    local delete_status
    delete_status="$(curl -sS -o /tmp/gitea-repo-del.out -w '%{http_code}' \
      --user "${owner}:${password}" \
      -X DELETE \
      "${instance_url}/api/v1/repos/${owner}/${old_repo}" || true)"
    if [[ "$delete_status" != "204" && "$delete_status" != "404" ]]; then
      cat /tmp/gitea-repo-del.out >&2 || true
      rm -f /tmp/gitea-repo-del.out
      die "Failed to remove legacy repo '${owner}/${old_repo}' (HTTP ${delete_status})"
    fi
    rm -f /tmp/gitea-repo-del.out
    log "Removed legacy repo '${owner}/${old_repo}' because '${owner}/${new_repo}' already exists"
    return 0
  fi
  if [[ "$new_status" != "404" ]]; then
    cat /tmp/gitea-repo-new.out >&2 || true
    rm -f /tmp/gitea-repo-new.out
    die "Failed to query target repo '${owner}/${new_repo}' (HTTP ${new_status})"
  fi
  rm -f /tmp/gitea-repo-new.out

  local rename_payload
  rename_payload="$(printf '{"name":"%s"}' "$new_repo")"
  local rename_status
  rename_status="$(curl -sS -o /tmp/gitea-repo-rename.out -w '%{http_code}' \
    --user "${owner}:${password}" \
    -H 'Content-Type: application/json' \
    -X PATCH \
    --data "$rename_payload" \
    "${instance_url}/api/v1/repos/${owner}/${old_repo}" || true)"
  if [[ "$rename_status" != "200" ]]; then
    cat /tmp/gitea-repo-rename.out >&2 || true
    rm -f /tmp/gitea-repo-rename.out
    die "Failed to rename repo '${owner}/${old_repo}' -> '${new_repo}' (HTTP ${rename_status})"
  fi
  rm -f /tmp/gitea-repo-rename.out

  log "Renamed legacy repo '${owner}/${old_repo}' to '${new_repo}'"
}

ensure_repo_with_branch_jenkinsfiles() {
  local repo_name="$1"
  local prod_jenkinsfile="$2"
  local dev_jenkinsfile="$3"
  local repo_label="$4"
  local file_path="Jenkinsfile"

  local gitea_http_port="${GITEA_HTTP_PORT:-3000}"
  local instance_url="${GITEA_ROOT_URL:-http://localhost:${gitea_http_port}/}"
  instance_url="${instance_url%/}"

  local owner="${GITEA_USER:-myuser}"
  local password="${GITEA_USER_PASSWORD:-password}"

  local create_body
  create_body="$(mktemp)"
  local create_payload
  create_payload="$(printf '{"name":"%s","auto_init":true,"private":true}' "$repo_name")"

  local create_status
  create_status="$(curl -sS -o "$create_body" -w '%{http_code}' \
    --user "${owner}:${password}" \
    -H 'Content-Type: application/json' \
    -X POST \
    --data "$create_payload" \
    "${instance_url}/api/v1/user/repos" || true)"

  if [[ "$create_status" != "201" && "$create_status" != "409" ]]; then
    cat "$create_body" >&2 || true
    rm -f "$create_body"
    die "Failed to create ${repo_label} repository '${owner}/${repo_name}' (HTTP ${create_status})"
  fi
  rm -f "$create_body"

  local repo_body
  repo_body="$(mktemp)"
  local repo_status
  repo_status="$(curl -sS -o "$repo_body" -w '%{http_code}' \
    --user "${owner}:${password}" \
    "${instance_url}/api/v1/repos/${owner}/${repo_name}" || true)"
  if [[ "$repo_status" != "200" ]]; then
    cat "$repo_body" >&2 || true
    rm -f "$repo_body"
    die "Failed to query repository metadata for '${owner}/${repo_name}' (HTTP ${repo_status})"
  fi

  local default_branch
  default_branch="$(tr -d '\n' <"$repo_body" | sed -n 's/.*"default_branch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  rm -f "$repo_body"
  if [[ -z "$default_branch" ]]; then
    default_branch="main"
  fi

  local file_url="${instance_url}/api/v1/repos/${owner}/${repo_name}/contents/${file_path}"

  put_repo_file() {
    local target_branch="$1"
    local content="$2"
    local content_b64
    content_b64="$(printf '%s' "$content" | base64 | tr -d '\n')"

    local get_body
    get_body="$(mktemp)"
    local get_status
    get_status="$(curl -sS -o "$get_body" -w '%{http_code}' \
      --user "${owner}:${password}" \
      "${file_url}?ref=${target_branch}" || true)"

    local existing_sha=""
    if [[ "$get_status" == "200" ]]; then
      existing_sha="$(tr -d '\n' <"$get_body" | sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
    elif [[ "$get_status" != "404" ]]; then
      cat "$get_body" >&2 || true
      rm -f "$get_body"
      die "Failed to query ${file_path} in branch '${target_branch}' (HTTP ${get_status})"
    fi
    rm -f "$get_body"

    local payload
    local write_method
    if [[ -n "$existing_sha" ]]; then
      payload="$(printf '{"content":"%s","message":"chore: set %s Jenkinsfile for %s","branch":"%s","sha":"%s"}' "$content_b64" "$repo_name" "$target_branch" "$target_branch" "$existing_sha")"
      write_method="PUT"
    else
      payload="$(printf '{"content":"%s","message":"chore: set %s Jenkinsfile for %s","branch":"%s"}' "$content_b64" "$repo_name" "$target_branch" "$target_branch")"
      write_method="POST"
    fi

    local write_body
    write_body="$(mktemp)"
    local write_status
    write_status="$(curl -sS -o "$write_body" -w '%{http_code}' \
      --user "${owner}:${password}" \
      -H 'Content-Type: application/json' \
      -X "$write_method" \
      --data "$payload" \
      "$file_url" || true)"

    if [[ "$write_status" != "200" && "$write_status" != "201" ]]; then
      cat "$write_body" >&2 || true
      rm -f "$write_body"
      die "Failed to ensure ${file_path} in branch '${target_branch}' (HTTP ${write_status})"
    fi
    rm -f "$write_body"
  }

  put_repo_file "$default_branch" "$prod_jenkinsfile"

  local branch_body
  branch_body="$(mktemp)"
  local branch_status
  branch_status="$(curl -sS -o "$branch_body" -w '%{http_code}' \
    --user "${owner}:${password}" \
    -H 'Content-Type: application/json' \
    -X POST \
    --data "$(printf '{"new_branch_name":"dev","old_ref_name":"%s"}' "$default_branch")" \
    "${instance_url}/api/v1/repos/${owner}/${repo_name}/branches" || true)"

  if [[ "$branch_status" != "201" && "$branch_status" != "409" ]]; then
    local branch_body_2
    branch_body_2="$(mktemp)"
    local branch_status_2
    branch_status_2="$(curl -sS -o "$branch_body_2" -w '%{http_code}' \
      --user "${owner}:${password}" \
      -H 'Content-Type: application/json' \
      -X POST \
      --data "$(printf '{"new_branch_name":"dev","old_branch_name":"%s"}' "$default_branch")" \
      "${instance_url}/api/v1/repos/${owner}/${repo_name}/branches" || true)"

    if [[ "$branch_status_2" != "201" && "$branch_status_2" != "409" ]]; then
      cat "$branch_body" >&2 || true
      cat "$branch_body_2" >&2 || true
      rm -f "$branch_body" "$branch_body_2"
      die "Failed to ensure dev branch in '${owner}/${repo_name}' (HTTP ${branch_status}/${branch_status_2})"
    fi
    rm -f "$branch_body_2"
  fi
  rm -f "$branch_body"

  put_repo_file "dev" "$dev_jenkinsfile"
  log "Ensured ${repo_label} repo '${owner}/${repo_name}' with branches '${default_branch}' and 'dev'"
}

ensure_example_pipeline_repo() {
  local auto_add="${GITEA_AUTO_ADD_EXAMPLE_PIPELINE:-true}"
  auto_add="$(printf '%s' "$auto_add" | tr '[:upper:]' '[:lower:]')"
  case "$auto_add" in
    1|true|yes|on) ;;
    *)
      log "Skipping example pipeline setup (GITEA_AUTO_ADD_EXAMPLE_PIPELINE=${GITEA_AUTO_ADD_EXAMPLE_PIPELINE:-false})"
      return 0
      ;;
  esac

  local template
  template="$(cat "${ROOT_DIR}/templates/example-pipeline.Jenkinsfile")"
  local prod_jenkinsfile="${template//__HELLO_MESSAGE__/hello prod world}"
  local dev_jenkinsfile="${template//__HELLO_MESSAGE__/hello dev world}"

  ensure_repo_with_branch_jenkinsfiles \
    "${GITEA_EXAMPLE_PIPELINE_REPO:-example-pipeline}" \
    "$prod_jenkinsfile" \
    "$dev_jenkinsfile" \
    "example-pipeline"
}

ensure_generate_library_repo() {
  local auto_add="${GITEA_AUTO_ADD_GENERATE_LIBRARY:-true}"
  auto_add="$(printf '%s' "$auto_add" | tr '[:upper:]' '[:lower:]')"
  case "$auto_add" in
    1|true|yes|on) ;;
    *)
      log "Skipping generate-library setup (GITEA_AUTO_ADD_GENERATE_LIBRARY=${GITEA_AUTO_ADD_GENERATE_LIBRARY:-false})"
      return 0
      ;;
  esac

  rename_legacy_generate_api_library_repo

  local jenkinsfile
  jenkinsfile="$(cat "${ROOT_DIR}/templates/generate-library.Jenkinsfile")"

  ensure_repo_with_branch_jenkinsfiles \
    "${GITEA_GENERATE_LIBRARY_REPO:-generate-library}" \
    "$jenkinsfile" \
    "$jenkinsfile" \
    "generate-library"

  ensure_generate_library_workflow
}

ensure_generate_library_workflow() {
  local gitea_http_port="${GITEA_HTTP_PORT:-3000}"
  local instance_url="${GITEA_ROOT_URL:-http://localhost:${gitea_http_port}/}"
  instance_url="${instance_url%/}"

  local owner="${GITEA_USER:-myuser}"
  local password="${GITEA_USER_PASSWORD:-password}"
  local repo_name="${GITEA_GENERATE_LIBRARY_REPO:-generate-library}"
  local file_path=".gitea/workflows/generate-library.yml"
  local source_repo_url="${GITEA_GENERATE_LIBRARY_WORKFLOW_SOURCE_REPO_URL:-$(resolve_local_playground_source_repo_url)}"
  local source_branch="${GITEA_GENERATE_LIBRARY_WORKFLOW_SOURCE_BRANCH:-main}"
  local service_host
  service_host="$(resolve_example_workflow_service_host)"
  local vault_addr
  vault_addr="$(resolve_example_workflow_vault_addr)"
  local vault_token
  vault_token="$(resolve_example_workflow_vault_token)"
  local default_pypi_repo="${NEXUS_PYPI_REPO:-pypi-public}"

  local repo_body
  repo_body="$(mktemp)"
  local repo_status
  repo_status="$(curl -sS -o "$repo_body" -w '%{http_code}' \
    --user "${owner}:${password}" \
    "${instance_url}/api/v1/repos/${owner}/${repo_name}" || true)"
  if [[ "$repo_status" != "200" ]]; then
    cat "$repo_body" >&2 || true
    rm -f "$repo_body"
    die "Failed to query repository metadata for '${owner}/${repo_name}' (HTTP ${repo_status})"
  fi

  local default_branch
  default_branch="$(tr -d '\n' <"$repo_body" | sed -n 's/.*"default_branch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  rm -f "$repo_body"
  if [[ -z "$default_branch" ]]; then
    default_branch="main"
  fi

  local workflow_content
  workflow_content="$(cat <<'EOF'
name: generate-library

on:
  push:
  workflow_dispatch:

env:
  PLAYGROUND_SOURCE_REPO_URL: "__SOURCE_REPO_URL__"
  PLAYGROUND_SOURCE_BRANCH: "__SOURCE_REPO_BRANCH__"
  LOCAL_SERVICE_HOST: "__LOCAL_SERVICE_HOST__"
  DEFAULT_NEXUS_PYPI_REPO: "__DEFAULT_NEXUS_PYPI_REPO__"

jobs:
  generate-library:
    runs-on: linux-amd64
    steps:
      - name: Prepare workspace
        run: |
          rm -rf playground .nexus.env

      - name: Install required system packages
        run: |
          set -euo pipefail
          export DEBIAN_FRONTEND=noninteractive
          apt-get update
          apt-get install -y git make python3 python3-pip python3-venv

      - name: Resolve Nexus credentials from Vault
        env:
          VAULT_ADDR: ${{ secrets.VAULT_ADDR }}
          VAULT_TOKEN: ${{ secrets.VAULT_TOKEN }}
        run: |
          set -euo pipefail

          if [ -z "${VAULT_ADDR:-}" ] || [ -z "${VAULT_TOKEN:-}" ]; then
            echo "VAULT_ADDR and VAULT_TOKEN secrets are required."
            exit 1
          fi

          vault_response="$(curl -fsS -H "X-Vault-Token: ${VAULT_TOKEN}" "${VAULT_ADDR%/}/v1/secret/data/services/nexus")"
          export VAULT_RESPONSE="${vault_response}"

          python3 - <<'PY' > .nexus.env
          import json
          import os
          
          data = json.loads(os.environ["VAULT_RESPONSE"]).get("data", {}).get("data", {})
          required = ("url", "admin_user", "admin_password")
          missing = [key for key in required if not data.get(key)]
          if missing:
              raise SystemExit(
                  "Vault secret secret/data/services/nexus is missing: " + ", ".join(missing)
              )
          
          nexus_url = data["url"].rstrip("/")
          local_service_host = os.environ["LOCAL_SERVICE_HOST"]
          nexus_url = (
              nexus_url.replace("http://127.0.0.1", "http://" + local_service_host)
              .replace("http://localhost", "http://" + local_service_host)
              .replace("https://127.0.0.1", "https://" + local_service_host)
              .replace("https://localhost", "https://" + local_service_host)
          )
          pypi_repo = data.get("pypi_repo") or os.environ["DEFAULT_NEXUS_PYPI_REPO"]
          
          print(f"NEXUS_URL={nexus_url}")
          print(f"NEXUS_USER={data['admin_user']}")
          print(f"NEXUS_PASSWORD={data['admin_password']}")
          print(f"NEXUS_PYPI_REPO={pypi_repo}")
          PY

      - name: Ensure Nexus PyPI repository
        run: |
          set -euo pipefail
          set -a
          . ./.nexus.env
          set +a
          python3 - <<'PY'
          import json
          import os
          import urllib.request
          from base64 import b64encode
          
          nexus_url = os.environ["NEXUS_URL"].rstrip("/")
          repo = os.environ["NEXUS_PYPI_REPO"]
          auth = b64encode(
              f"{os.environ['NEXUS_USER']}:{os.environ['NEXUS_PASSWORD']}".encode()
          ).decode()
          headers = {"Authorization": f"Basic {auth}"}
          
          req = urllib.request.Request(f"{nexus_url}/service/rest/v1/repositories", headers=headers)
          repos = json.load(urllib.request.urlopen(req))
          if any(item.get("name") == repo for item in repos):
              raise SystemExit(0)
          
          payload = json.dumps(
              {
                  "name": repo,
                  "online": True,
                  "storage": {
                      "blobStoreName": "default",
                      "strictContentTypeValidation": True,
                      "writePolicy": "ALLOW",
                  },
              }
          ).encode()
          req = urllib.request.Request(
              f"{nexus_url}/service/rest/v1/repositories/pypi/hosted",
              data=payload,
              headers={
                  "Authorization": f"Basic {auth}",
                  "Content-Type": "application/json",
              },
              method="POST",
          )
          urllib.request.urlopen(req)
          PY

      - name: Clone source repository
        run: |
          set -euo pipefail
          echo "Cloning ${PLAYGROUND_SOURCE_REPO_URL} (branch ${PLAYGROUND_SOURCE_BRANCH})"
          git clone --depth 1 --branch "${PLAYGROUND_SOURCE_BRANCH}" "${PLAYGROUND_SOURCE_REPO_URL}" playground

      - name: Validate API Makefile
        run: |
          set -euo pipefail
          cd playground/api
          if ! grep -Eq '(^|[[:space:]])library-generate([[:space:]:]|$)' Makefile; then
            echo "The checked-out source at ${PLAYGROUND_SOURCE_REPO_URL} branch ${PLAYGROUND_SOURCE_BRANCH} does not provide 'make library-generate'."
            exit 1
          fi

      - name: Generate GraphQL client library
        run: |
          set -euo pipefail
          cd playground/api
          make library-generate MODE=bare LIBRARY_SCHEMA_SOURCE=local
          test -d graphql-library/generated/fastapi_graphql_client

      - name: Build and upload package to Nexus
        run: |
          set -euo pipefail
          set -a
          . ./.nexus.env
          set +a
          cd playground/api/graphql-library
          rm -rf .venv-gitea-generate
          python3 -m venv .venv-gitea-generate
          . .venv-gitea-generate/bin/activate
          python -m pip install --upgrade pip build twine
          python3 - <<'PY'
          import datetime
          import os
          import pathlib
          import re
          
          pyproject = pathlib.Path("pyproject.toml")
          content = pyproject.read_text()
          match = re.search(r'^version = "([^"]+)"', content, re.MULTILINE)
          if not match:
              raise SystemExit("Could not determine package version from pyproject.toml")
          
          build_number = os.environ.get("GITHUB_RUN_NUMBER") or datetime.datetime.utcnow().strftime("%Y%m%d%H%M%S")
          new_version = f"{match.group(1)}.post{build_number}"
          updated = re.sub(
              r'^version = "[^"]+"',
              f'version = "{new_version}"',
              content,
              count=1,
              flags=re.MULTILINE,
          )
          pyproject.write_text(updated)
          pathlib.Path(".package-version").write_text(new_version + "\n")
          print(f"Using package version {new_version}")
          PY
          python3 -m build
          upload_url="${NEXUS_URL%/}/repository/${NEXUS_PYPI_REPO}/"
          attempts=6
          for attempt in $(seq 1 "$attempts"); do
            if twine upload --non-interactive --verbose --repository-url "$upload_url" -u "${NEXUS_USER}" -p "${NEXUS_PASSWORD}" dist/*; then
              exit 0
            fi
            if [ "$attempt" -eq "$attempts" ]; then
              echo "Twine upload failed after ${attempts} attempts."
              exit 1
            fi
            sleep 10
          done

      - name: Cleanup
        if: always()
        run: |
          rm -rf playground .nexus.env
EOF
)"
  workflow_content="${workflow_content//__SOURCE_REPO_URL__/$source_repo_url}"
  workflow_content="${workflow_content//__SOURCE_REPO_BRANCH__/$source_branch}"
  workflow_content="${workflow_content//__LOCAL_SERVICE_HOST__/$service_host}"
  workflow_content="${workflow_content//__DEFAULT_NEXUS_PYPI_REPO__/$default_pypi_repo}"

  ensure_repo_file_in_branch \
    "$instance_url" \
    "$owner" \
    "$password" \
    "$repo_name" \
    "$file_path" \
    "$default_branch" \
    "chore: sync generate-library gitea workflow" \
    "$workflow_content"
  ensure_repo_file_in_branch \
    "$instance_url" \
    "$owner" \
    "$password" \
    "$repo_name" \
    "$file_path" \
    "dev" \
    "chore: sync generate-library gitea workflow" \
    "$workflow_content"

  ensure_repo_actions_secret \
    "$instance_url" \
    "$owner" \
    "$password" \
    "$repo_name" \
    "VAULT_ADDR" \
    "$vault_addr" \
    "Vault API URL for managed generate-library workflows"
  ensure_repo_actions_secret \
    "$instance_url" \
    "$owner" \
    "$password" \
    "$repo_name" \
    "VAULT_TOKEN" \
    "$vault_token" \
    "Vault token for managed generate-library workflows"

  log "Ensured generate-library workflow in '${owner}/${repo_name}:${file_path}'"
}

ensure_library_example_client_repo() {
  local auto_add="${GITEA_AUTO_ADD_LIBRARY_EXAMPLE_CLIENT:-true}"
  auto_add="$(printf '%s' "$auto_add" | tr '[:upper:]' '[:lower:]')"
  case "$auto_add" in
    1|true|yes|on) ;;
    *)
      log "Skipping library-example-client setup (GITEA_AUTO_ADD_LIBRARY_EXAMPLE_CLIENT=${GITEA_AUTO_ADD_LIBRARY_EXAMPLE_CLIENT:-false})"
      return 0
      ;;
  esac

  local jenkinsfile
  jenkinsfile="$(cat "${ROOT_DIR}/templates/library-example-client.Jenkinsfile")"

  ensure_repo_with_branch_jenkinsfiles \
    "${GITEA_LIBRARY_EXAMPLE_CLIENT_REPO:-library-example-client}" \
    "$jenkinsfile" \
    "$jenkinsfile" \
    "library-example-client"

  ensure_library_example_client_workflow
}

ensure_library_example_client_workflow() {
  local gitea_http_port="${GITEA_HTTP_PORT:-3000}"
  local instance_url="${GITEA_ROOT_URL:-http://localhost:${gitea_http_port}/}"
  instance_url="${instance_url%/}"

  local owner="${GITEA_USER:-myuser}"
  local password="${GITEA_USER_PASSWORD:-password}"
  local repo_name="${GITEA_LIBRARY_EXAMPLE_CLIENT_REPO:-library-example-client}"
  local file_path=".gitea/workflows/library-example-client.yml"
  local source_repo_url="${GITEA_LIBRARY_EXAMPLE_CLIENT_WORKFLOW_SOURCE_REPO_URL:-$(resolve_local_playground_source_repo_url)}"
  local source_branch="${GITEA_LIBRARY_EXAMPLE_CLIENT_WORKFLOW_SOURCE_BRANCH:-main}"
  local graphql_url
  graphql_url="$(resolve_example_workflow_graphql_url)"
  local service_host
  service_host="$(resolve_example_workflow_service_host)"
  local vault_addr
  vault_addr="$(resolve_example_workflow_vault_addr)"
  local vault_token
  vault_token="$(resolve_example_workflow_vault_token)"
  local default_pypi_repo="${NEXUS_PYPI_REPO:-pypi-public}"

  local repo_body
  repo_body="$(mktemp)"
  local repo_status
  repo_status="$(curl -sS -o "$repo_body" -w '%{http_code}' \
    --user "${owner}:${password}" \
    "${instance_url}/api/v1/repos/${owner}/${repo_name}" || true)"
  if [[ "$repo_status" != "200" ]]; then
    cat "$repo_body" >&2 || true
    rm -f "$repo_body"
    die "Failed to query repository metadata for '${owner}/${repo_name}' (HTTP ${repo_status})"
  fi

  local default_branch
  default_branch="$(tr -d '\n' <"$repo_body" | sed -n 's/.*"default_branch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  rm -f "$repo_body"
  if [[ -z "$default_branch" ]]; then
    default_branch="main"
  fi

  local workflow_content
  workflow_content="$(cat <<'EOF'
name: library-example-client

on:
  push:
  workflow_dispatch:

env:
  PLAYGROUND_SOURCE_REPO_URL: "__SOURCE_REPO_URL__"
  PLAYGROUND_SOURCE_BRANCH: "__SOURCE_REPO_BRANCH__"
  GRAPHQL_URL: "__GRAPHQL_URL__"
  LOCAL_SERVICE_HOST: "__LOCAL_SERVICE_HOST__"
  DEFAULT_NEXUS_PYPI_REPO: "__DEFAULT_NEXUS_PYPI_REPO__"

jobs:
  company-client:
    runs-on: linux-amd64
    steps:
      - name: Prepare workspace
        run: |
          rm -rf playground .nexus.env

      - name: Clone source repository
        run: |
          set -euo pipefail
          echo "Cloning ${PLAYGROUND_SOURCE_REPO_URL} (branch ${PLAYGROUND_SOURCE_BRANCH})"
          git clone --depth 1 --branch "${PLAYGROUND_SOURCE_BRANCH}" "${PLAYGROUND_SOURCE_REPO_URL}" playground
          test -f playground/api/example-client/company.py

      - name: Resolve Nexus credentials from Vault
        env:
          VAULT_ADDR: ${{ secrets.VAULT_ADDR }}
          VAULT_TOKEN: ${{ secrets.VAULT_TOKEN }}
        run: |
          set -euo pipefail

          if [ -z "${VAULT_ADDR:-}" ] || [ -z "${VAULT_TOKEN:-}" ]; then
            echo "VAULT_ADDR and VAULT_TOKEN secrets are required."
            exit 1
          fi

          vault_response="$(curl -fsS -H "X-Vault-Token: ${VAULT_TOKEN}" "${VAULT_ADDR%/}/v1/secret/data/services/nexus")"
          export VAULT_RESPONSE="${vault_response}"

          python3 -c 'import json, os, sys; from urllib.parse import quote, urlsplit, urlunsplit; data = json.loads(os.environ["VAULT_RESPONSE"]).get("data", {}).get("data", {}); missing = [key for key in ("url", "regular_user", "regular_password") if not data.get(key)]; assert not missing, "Vault secret secret/data/services/nexus is missing: " + ", ".join(missing); base_url = data["url"].rstrip("/"); local_service_host = os.environ["LOCAL_SERVICE_HOST"]; parts = urlsplit(base_url); host_name = parts.hostname or ""; port = f":{parts.port}" if parts.port else ""; base_url = urlunsplit((parts.scheme, f"{local_service_host}{port}", parts.path, parts.query, parts.fragment)) if host_name in {"127.0.0.1", "localhost"} else base_url; pypi_repo = data.get("pypi_repo") or os.environ["DEFAULT_NEXUS_PYPI_REPO"]; simple_url = base_url.rstrip("/") + "/repository/" + pypi_repo + "/simple"; simple_parts = urlsplit(simple_url); host = simple_parts.hostname or ""; port = f":{simple_parts.port}" if simple_parts.port else ""; userinfo = "{}:{}".format(quote(data["regular_user"], safe=""), quote(data["regular_password"], safe="")); auth_url = urlunsplit((simple_parts.scheme, f"{userinfo}@{host}{port}", simple_parts.path, simple_parts.query, simple_parts.fragment)); print(f"NEXUS_SIMPLE_URL={auth_url}"); print(f"NEXUS_HOST={host}"); print(f"NEXUS_PYPI_REPO={pypi_repo}")' > .nexus.env

      - name: Install generated GraphQL client from Nexus
        run: |
          set -euo pipefail
          unset SSL_CERT_FILE REQUESTS_CA_BUNDLE CURL_CA_BUNDLE
          export DEBIAN_FRONTEND=noninteractive
          apt-get update
          apt-get install -y python3-pip python3-venv
          . ./.nexus.env
          rm -rf .venv-library-example-client
          python3 -m venv .venv-library-example-client
          . .venv-library-example-client/bin/activate
          python -m pip install --upgrade pip
          python -m pip install \
            --index-url https://pypi.org/simple \
            --extra-index-url "${NEXUS_SIMPLE_URL}" \
            --trusted-host "${NEXUS_HOST}" \
            fastapi-graphql-client

      - name: Run company.py workflow with valid data
        env:
          COMPANY_CLIENT_DISABLE_LOCAL_BOOTSTRAP: "1"
          FORCE_COLOR: "1"
        run: |
          set -euo pipefail
          export FASTAPI_BASIC_AUTH_USERNAME="${FASTAPI_BASIC_AUTH_USERNAME:-admin}"
          export FASTAPI_BASIC_AUTH_PASSWORD="${FASTAPI_BASIC_AUTH_PASSWORD:-password}"
          . .venv-library-example-client/bin/activate
          python playground/api/example-client/company.py \
            --graphql-url "${GRAPHQL_URL}" \
            workflow \
            --employee-name Erika \
            --employee-surname Mustermann \
            --employee-role Developer \
            --updated-employee-name Erika \
            --updated-employee-surname Mustermann \
            --updated-employee-role "Senior Developer"

      - name: Cleanup
        if: always()
        run: |
          rm -rf playground .nexus.env .venv-library-example-client
EOF
)"
  workflow_content="${workflow_content//__SOURCE_REPO_URL__/$source_repo_url}"
  workflow_content="${workflow_content//__SOURCE_REPO_BRANCH__/$source_branch}"
  workflow_content="${workflow_content//__GRAPHQL_URL__/$graphql_url}"
  workflow_content="${workflow_content//__LOCAL_SERVICE_HOST__/$service_host}"
  workflow_content="${workflow_content//__DEFAULT_NEXUS_PYPI_REPO__/$default_pypi_repo}"

  ensure_repo_file_in_branch \
    "$instance_url" \
    "$owner" \
    "$password" \
    "$repo_name" \
    "$file_path" \
    "$default_branch" \
    "chore: sync library-example-client gitea workflow" \
    "$workflow_content"
  ensure_repo_file_in_branch \
    "$instance_url" \
    "$owner" \
    "$password" \
    "$repo_name" \
    "$file_path" \
    "dev" \
    "chore: sync library-example-client gitea workflow" \
    "$workflow_content"

  ensure_repo_actions_secret \
    "$instance_url" \
    "$owner" \
    "$password" \
    "$repo_name" \
    "VAULT_ADDR" \
    "$vault_addr" \
    "Vault API URL for managed library-example-client workflows"
  ensure_repo_actions_secret \
    "$instance_url" \
    "$owner" \
    "$password" \
    "$repo_name" \
    "VAULT_TOKEN" \
    "$vault_token" \
    "Vault token for managed library-example-client workflows"

  log "Ensured library-example-client workflow in '${owner}/${repo_name}:${file_path}'"
}

ensure_add_employee_repo() {
  local auto_add="${GITEA_AUTO_ADD_ADD_EMPLOYEE:-true}"
  auto_add="$(printf '%s' "$auto_add" | tr '[:upper:]' '[:lower:]')"
  case "$auto_add" in
    1|true|yes|on) ;;
    *)
      log "Skipping add-employee setup (GITEA_AUTO_ADD_ADD_EMPLOYEE=${GITEA_AUTO_ADD_ADD_EMPLOYEE:-false})"
      return 0
      ;;
  esac

  local jenkinsfile
  jenkinsfile="$(cat "${ROOT_DIR}/templates/add-employee.Jenkinsfile")"

  ensure_repo_with_branch_jenkinsfiles \
    "${GITEA_ADD_EMPLOYEE_REPO:-add-employee}" \
    "$jenkinsfile" \
    "$jenkinsfile" \
    "add-employee"

  ensure_add_employee_workflow
}

ensure_print_employee_repo() {
  local auto_add="${GITEA_AUTO_ADD_PRINT_EMPLOYEE:-true}"
  auto_add="$(printf '%s' "$auto_add" | tr '[:upper:]' '[:lower:]')"
  case "$auto_add" in
    1|true|yes|on) ;;
    *)
      log "Skipping print-employee setup (GITEA_AUTO_ADD_PRINT_EMPLOYEE=${GITEA_AUTO_ADD_PRINT_EMPLOYEE:-false})"
      return 0
      ;;
  esac

  local jenkinsfile
  jenkinsfile="$(cat "${ROOT_DIR}/templates/print-employee.Jenkinsfile")"

  ensure_repo_with_branch_jenkinsfiles \
    "${GITEA_PRINT_EMPLOYEE_REPO:-print-employee}" \
    "$jenkinsfile" \
    "$jenkinsfile" \
    "print-employee"

  ensure_print_employee_workflow
}

ensure_print_employee_workflow() {
  local gitea_http_port="${GITEA_HTTP_PORT:-3000}"
  local instance_url="${GITEA_ROOT_URL:-http://localhost:${gitea_http_port}/}"
  instance_url="${instance_url%/}"

  local owner="${GITEA_USER:-myuser}"
  local password="${GITEA_USER_PASSWORD:-password}"
  local repo_name="${GITEA_PRINT_EMPLOYEE_REPO:-print-employee}"
  local file_path=".gitea/workflows/print-employee.yml"
  local source_repo_url="${GITEA_PRINT_EMPLOYEE_WORKFLOW_SOURCE_REPO_URL:-$(resolve_local_playground_source_repo_url)}"
  local source_branch="${GITEA_PRINT_EMPLOYEE_WORKFLOW_SOURCE_BRANCH:-main}"
  local graphql_url
  graphql_url="$(resolve_print_employee_workflow_graphql_url)"

  local repo_body
  repo_body="$(mktemp)"
  local repo_status
  repo_status="$(curl -sS -o "$repo_body" -w '%{http_code}' \
    --user "${owner}:${password}" \
    "${instance_url}/api/v1/repos/${owner}/${repo_name}" || true)"
  if [[ "$repo_status" != "200" ]]; then
    cat "$repo_body" >&2 || true
    rm -f "$repo_body"
    die "Failed to query repository metadata for '${owner}/${repo_name}' (HTTP ${repo_status})"
  fi

  local default_branch
  default_branch="$(tr -d '\n' <"$repo_body" | sed -n 's/.*"default_branch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  rm -f "$repo_body"
  if [[ -z "$default_branch" ]]; then
    default_branch="main"
  fi

  local workflow_content
  workflow_content="$(cat <<'EOF'
name: print-employee

on:
  workflow_dispatch:
    inputs:
      employee_id:
        description: Employee id to fetch
        required: true
        default: "1"

env:
  PLAYGROUND_SOURCE_REPO_URL: "__SOURCE_REPO_URL__"
  PLAYGROUND_SOURCE_BRANCH: "__SOURCE_REPO_BRANCH__"
  GRAPHQL_URL: "__GRAPHQL_URL__"

jobs:
  print-employee:
    runs-on: linux-amd64
    steps:
      - name: Prepare workspace
        run: |
          rm -rf playground

      - name: Install required system packages
        run: |
          set -euo pipefail
          export DEBIAN_FRONTEND=noninteractive
          apt-get update
          apt-get install -y git make python3-venv

      - name: Clone source repository
        run: |
          set -euo pipefail
          echo "Cloning ${PLAYGROUND_SOURCE_REPO_URL} (branch ${PLAYGROUND_SOURCE_BRANCH})"
          git clone --depth 1 --branch "${PLAYGROUND_SOURCE_BRANCH}" "${PLAYGROUND_SOURCE_REPO_URL}" playground
          test -f playground/api/example-client/company.py

      - name: Validate Example Client CLI
        run: |
          set -euo pipefail
          if ! (cd playground/api && example-client/company.py employee get --help 2>&1 | grep -q -- '--employee-id'); then
            echo "The checked-out source at ${PLAYGROUND_SOURCE_REPO_URL} branch ${PLAYGROUND_SOURCE_BRANCH} does not provide employee lookup support in api/example-client/company.py."
            exit 1
          fi

      - name: Generate local GraphQL client runtime
        run: |
          set -euo pipefail
          make -C playground/api library-generate MODE=bare LIBRARY_SCHEMA_SOURCE=local

      - name: Print employee details
        env:
          FORCE_COLOR: "1"
          WORKFLOW_INPUT_EMPLOYEE_ID: "${{ inputs.employee_id }}"
          EVENT_INPUT_EMPLOYEE_ID: "${{ github.event.inputs.employee_id }}"
        run: |
          set -euo pipefail
          export FASTAPI_BASIC_AUTH_USERNAME="${FASTAPI_BASIC_AUTH_USERNAME:-admin}"
          export FASTAPI_BASIC_AUTH_PASSWORD="${FASTAPI_BASIC_AUTH_PASSWORD:-password}"
          employee_id="${WORKFLOW_INPUT_EMPLOYEE_ID:-}"
          if [ -z "${employee_id}" ]; then
            employee_id="${EVENT_INPUT_EMPLOYEE_ID:-}"
          fi
          if [ -z "${employee_id}" ] && [ -n "${GITHUB_EVENT_PATH:-}" ] && [ -f "${GITHUB_EVENT_PATH}" ]; then
            employee_id="$(python3 -c 'import json, os; event_path = os.environ.get("GITHUB_EVENT_PATH", ""); payload = json.load(open(event_path, "r", encoding="utf-8")) if event_path and os.path.isfile(event_path) else {}; print((((payload.get("inputs") or {}).get("employee_id")) or ""), end="")')"
          fi
          if [ -z "${employee_id}" ]; then
            employee_id="1"
          fi
          PYTHONPATH="playground/api/graphql-library/generated${PYTHONPATH:+:${PYTHONPATH}}" \
          playground/api/graphql-library/.venv/bin/python \
            playground/api/example-client/company.py \
            --graphql-url "${GRAPHQL_URL}" \
            employee get \
            --employee-id "${employee_id}"

      - name: Cleanup
        if: always()
        run: |
          rm -rf playground
EOF
)"
  workflow_content="${workflow_content//__SOURCE_REPO_URL__/$source_repo_url}"
  workflow_content="${workflow_content//__SOURCE_REPO_BRANCH__/$source_branch}"
  workflow_content="${workflow_content//__GRAPHQL_URL__/$graphql_url}"

  ensure_repo_file_in_branch \
    "$instance_url" \
    "$owner" \
    "$password" \
    "$repo_name" \
    "$file_path" \
    "$default_branch" \
    "chore: sync print-employee gitea workflow" \
    "$workflow_content"
  ensure_repo_file_in_branch \
    "$instance_url" \
    "$owner" \
    "$password" \
    "$repo_name" \
    "$file_path" \
    "dev" \
    "chore: sync print-employee gitea workflow" \
    "$workflow_content"

  log "Ensured print-employee workflow in '${owner}/${repo_name}:${file_path}'"
}

ensure_add_employee_workflow() {
  local gitea_http_port="${GITEA_HTTP_PORT:-3000}"
  local instance_url="${GITEA_ROOT_URL:-http://localhost:${gitea_http_port}/}"
  instance_url="${instance_url%/}"

  local owner="${GITEA_USER:-myuser}"
  local password="${GITEA_USER_PASSWORD:-password}"
  local repo_name="${GITEA_ADD_EMPLOYEE_REPO:-add-employee}"
  local file_path=".gitea/workflows/add-employee.yml"
  local source_repo_url="${GITEA_ADD_EMPLOYEE_WORKFLOW_SOURCE_REPO_URL:-$(resolve_local_playground_source_repo_url)}"
  local source_branch="${GITEA_ADD_EMPLOYEE_WORKFLOW_SOURCE_BRANCH:-main}"
  local graphql_url
  graphql_url="$(resolve_add_employee_workflow_graphql_url)"
  local vault_addr
  vault_addr="$(resolve_example_workflow_vault_addr)"
  local vault_token
  vault_token="$(resolve_example_workflow_vault_token)"
  local default_pypi_repo="${NEXUS_PYPI_REPO:-pypi-public}"

  local repo_body
  repo_body="$(mktemp)"
  local repo_status
  repo_status="$(curl -sS -o "$repo_body" -w '%{http_code}' \
    --user "${owner}:${password}" \
    "${instance_url}/api/v1/repos/${owner}/${repo_name}" || true)"
  if [[ "$repo_status" != "200" ]]; then
    cat "$repo_body" >&2 || true
    rm -f "$repo_body"
    die "Failed to query repository metadata for '${owner}/${repo_name}' (HTTP ${repo_status})"
  fi

  local default_branch
  default_branch="$(tr -d '\n' <"$repo_body" | sed -n 's/.*"default_branch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  rm -f "$repo_body"
  if [[ -z "$default_branch" ]]; then
    default_branch="main"
  fi

  local workflow_content
  workflow_content="$(cat <<'EOF'
name: add-employee

on:
  push:
  workflow_dispatch:
    inputs:
      employee_name:
        description: Employee first name
        required: false
        default: Hans
      employee_surname:
        description: Employee surname
        required: false
        default: Wurst
      employee_role:
        description: Employee role
        required: false
        default: Developer

env:
  PLAYGROUND_SOURCE_REPO_URL: "__SOURCE_REPO_URL__"
  PLAYGROUND_SOURCE_BRANCH: "__SOURCE_REPO_BRANCH__"
  GRAPHQL_URL: "__GRAPHQL_URL__"
  DEFAULT_NEXUS_PYPI_REPO: "__DEFAULT_NEXUS_PYPI_REPO__"

jobs:
  add-employee:
    runs-on: linux-amd64
    steps:
      - name: Prepare workspace
        run: |
          rm -rf playground .nexus.env

      - name: Install required system packages
        run: |
          set -euo pipefail
          export DEBIAN_FRONTEND=noninteractive
          apt-get update
          apt-get install -y git python3-pip python3-venv

      - name: Resolve Nexus credentials from Vault
        env:
          VAULT_ADDR: ${{ secrets.VAULT_ADDR }}
          VAULT_TOKEN: ${{ secrets.VAULT_TOKEN }}
        run: |
          set -euo pipefail

          if [ -z "${VAULT_ADDR:-}" ] || [ -z "${VAULT_TOKEN:-}" ]; then
            echo "VAULT_ADDR and VAULT_TOKEN secrets are required."
            exit 1
          fi

          vault_response="$(curl -fsS -H "X-Vault-Token: ${VAULT_TOKEN}" "${VAULT_ADDR%/}/v1/secret/data/services/nexus")"
          export VAULT_RESPONSE="${vault_response}"

          python3 -c 'import json, os; data = json.loads(os.environ["VAULT_RESPONSE"]).get("data", {}).get("data", {}); missing = [key for key in ("url", "admin_user", "admin_password") if not data.get(key)]; assert not missing, "Vault secret secret/data/services/nexus is missing: " + ", ".join(missing); nexus_url = data["url"].rstrip("/"); nexus_url = nexus_url.replace("http://127.0.0.1", "http://host.docker.internal").replace("http://localhost", "http://host.docker.internal").replace("https://127.0.0.1", "https://host.docker.internal").replace("https://localhost", "https://host.docker.internal"); pypi_repo = data.get("pypi_repo") or os.environ["DEFAULT_NEXUS_PYPI_REPO"]; print("NEXUS_URL=" + nexus_url); print("NEXUS_USER=" + data["admin_user"]); print("NEXUS_PASSWORD=" + data["admin_password"]); print("NEXUS_PYPI_REPO=" + pypi_repo)' > .nexus.env

      - name: Clone source repository
        run: |
          set -euo pipefail
          echo "Cloning ${PLAYGROUND_SOURCE_REPO_URL} (branch ${PLAYGROUND_SOURCE_BRANCH})"
          git clone --depth 1 --branch "${PLAYGROUND_SOURCE_BRANCH}" "${PLAYGROUND_SOURCE_REPO_URL}" playground
          test -f playground/api/example-client/company.py

      - name: Validate Example Client CLI
        run: |
          set -euo pipefail
          if ! (cd playground/api && example-client/company.py employee add --help 2>&1 | grep -q -- '--employee-role'); then
            echo "The checked-out source at ${PLAYGROUND_SOURCE_REPO_URL} branch ${PLAYGROUND_SOURCE_BRANCH} does not provide role-based add-employee support in api/example-client/company.py."
            exit 1
          fi

      - name: Install generated GraphQL client from Nexus
        run: |
          set -euo pipefail
          unset SSL_CERT_FILE REQUESTS_CA_BUNDLE CURL_CA_BUNDLE
          . ./.nexus.env
          rm -rf .venv-add-employee
          python3 -m venv .venv-add-employee
          . .venv-add-employee/bin/activate
          python -m pip install --upgrade pip
          nexus_simple_url="${NEXUS_URL%/}/repository/${NEXUS_PYPI_REPO}/simple"
          nexus_host="$(printf '%s' "${NEXUS_URL}" | sed -E 's#^[a-zA-Z]+://([^/:]+).*#\1#')"
          python -m pip install \
            --index-url https://pypi.org/simple \
            --extra-index-url "${nexus_simple_url}" \
            --trusted-host "${nexus_host}" \
            "fastapi-graphql-client${FASTAPI_GRAPHQL_CLIENT_VERSION:+==${FASTAPI_GRAPHQL_CLIENT_VERSION}}"

      - name: Run Example Client
        env:
          COMPANY_CLIENT_DISABLE_LOCAL_BOOTSTRAP: "1"
          FORCE_COLOR: "1"
        run: |
          set -euo pipefail
          export FASTAPI_BASIC_AUTH_USERNAME="${FASTAPI_BASIC_AUTH_USERNAME:-admin}"
          export FASTAPI_BASIC_AUTH_PASSWORD="${FASTAPI_BASIC_AUTH_PASSWORD:-password}"
          employee_name="${{ github.event.inputs.employee_name }}"
          employee_surname="${{ github.event.inputs.employee_surname }}"
          employee_role="${{ github.event.inputs.employee_role }}"
          if [ -z "${employee_name}" ]; then employee_name="Hans"; fi
          if [ -z "${employee_surname}" ]; then employee_surname="Wurst"; fi
          if [ -z "${employee_role}" ]; then employee_role="Developer"; fi
          . .venv-add-employee/bin/activate
          python playground/api/example-client/company.py \
            --graphql-url "${GRAPHQL_URL}" \
            employee add \
            --employee-name "${employee_name}" \
            --employee-surname "${employee_surname}" \
            --employee-role "${employee_role}"

      - name: Cleanup
        if: always()
        run: |
          rm -rf playground .nexus.env .venv-add-employee
EOF
)"
  workflow_content="${workflow_content//__SOURCE_REPO_URL__/$source_repo_url}"
  workflow_content="${workflow_content//__SOURCE_REPO_BRANCH__/$source_branch}"
  workflow_content="${workflow_content//__GRAPHQL_URL__/$graphql_url}"
  workflow_content="${workflow_content//__DEFAULT_NEXUS_PYPI_REPO__/$default_pypi_repo}"

  ensure_repo_file_in_branch \
    "$instance_url" \
    "$owner" \
    "$password" \
    "$repo_name" \
    "$file_path" \
    "$default_branch" \
    "chore: sync add-employee gitea workflow" \
    "$workflow_content"
  ensure_repo_file_in_branch \
    "$instance_url" \
    "$owner" \
    "$password" \
    "$repo_name" \
    "$file_path" \
    "dev" \
    "chore: sync add-employee gitea workflow" \
    "$workflow_content"

  ensure_repo_actions_secret \
    "$instance_url" \
    "$owner" \
    "$password" \
    "$repo_name" \
    "VAULT_ADDR" \
    "$vault_addr" \
    "Vault API URL for managed add-employee workflows"
  ensure_repo_actions_secret \
    "$instance_url" \
    "$owner" \
    "$password" \
    "$repo_name" \
    "VAULT_TOKEN" \
    "$vault_token" \
    "Vault token for managed add-employee workflows"

  log "Ensured add-employee workflow in '${owner}/${repo_name}:${file_path}'"
}
