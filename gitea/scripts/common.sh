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
  remove_example_workflow_repo
  ensure_example_workflow_repo
  ensure_jenkins_example_repo
  ensure_generate_library_repo
  ensure_library_example_client_repo
  ensure_add_employee_repo
}

ensure_example_workflow_repo() {
  local auto_add="${GITEA_AUTO_ADD_EXAMPLE_WORKFLOW:-true}"
  auto_add="$(printf '%s' "$auto_add" | tr '[:upper:]' '[:lower:]')"
  case "$auto_add" in
    1|true|yes|on) ;;
    *)
      log "Skipping example workflow setup (GITEA_AUTO_ADD_EXAMPLE_WORKFLOW=${GITEA_AUTO_ADD_EXAMPLE_WORKFLOW:-false})"
      return 0
      ;;
  esac

  local gitea_http_port="${GITEA_HTTP_PORT:-3000}"
  local instance_url="${GITEA_ROOT_URL:-http://localhost:${gitea_http_port}/}"
  instance_url="${instance_url%/}"

  local owner="${GITEA_USER:-myuser}"
  local password="${GITEA_USER_PASSWORD:-password}"
  local repo_name="${GITEA_EXAMPLE_REPO:-actions-example}"
  local file_path=".gitea/workflows/actions-example.yml"
  local file_url="${instance_url}/api/v1/repos/${owner}/${repo_name}/contents/${file_path}"

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
    die "Failed to create example repository '${owner}/${repo_name}' (HTTP ${create_status})"
  fi
  rm -f "$create_body"

  local workflow_content
  workflow_content="$(cat <<'EOF'
name: actions-example

on:
  push:
  workflow_dispatch:

jobs:
  hello:
    runs-on: linux-amd64
    steps:
      - name: Print hello world
        run: echo "hello world"
EOF
)"
  local workflow_b64
  workflow_b64="$(printf '%s' "$workflow_content" | base64 | tr -d '\n')"

  local get_body
  get_body="$(mktemp)"
  local get_status
  get_status="$(curl -sS -o "$get_body" -w '%{http_code}' \
    --user "${owner}:${password}" \
    "$file_url" || true)"

  local existing_sha=""
  if [[ "$get_status" == "200" ]]; then
    existing_sha="$(tr -d '\n' <"$get_body" | sed -n 's/.*"sha":"\([^"]*\)".*/\1/p' | head -n1)"
  elif [[ "$get_status" != "404" ]]; then
    cat "$get_body" >&2 || true
    rm -f "$get_body"
    die "Failed to query example workflow file in '${owner}/${repo_name}' (HTTP ${get_status})"
  fi
  rm -f "$get_body"

  local update_payload
  local update_method
  if [[ -n "$existing_sha" ]]; then
    update_payload="$(printf '{"content":"%s","message":"chore: add hello world gitea action","sha":"%s"}' "$workflow_b64" "$existing_sha")"
    update_method="PUT"
  else
    update_payload="$(printf '{"content":"%s","message":"chore: add hello world gitea action"}' "$workflow_b64")"
    update_method="POST"
  fi

  local update_body
  update_body="$(mktemp)"
  local update_status
  update_status="$(curl -sS -o "$update_body" -w '%{http_code}' \
    --user "${owner}:${password}" \
    -H 'Content-Type: application/json' \
    -X "$update_method" \
    --data "$update_payload" \
    "$file_url" || true)"

  if [[ "$update_status" != "200" && "$update_status" != "201" ]]; then
    cat "$update_body" >&2 || true
    rm -f "$update_body"
    die "Failed to ensure example workflow in '${owner}/${repo_name}' (HTTP ${update_status})"
  fi
  rm -f "$update_body"

  log "Ensured example workflow in '${owner}/${repo_name}:${file_path}'"
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
  local repo_name="${GITEA_EXAMPLE_REPO:-actions-example}"

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

ensure_jenkins_example_repo() {
  local auto_add="${GITEA_AUTO_ADD_JENKINS_EXAMPLE:-true}"
  auto_add="$(printf '%s' "$auto_add" | tr '[:upper:]' '[:lower:]')"
  case "$auto_add" in
    1|true|yes|on) ;;
    *)
      log "Skipping jenkins example setup (GITEA_AUTO_ADD_JENKINS_EXAMPLE=${GITEA_AUTO_ADD_JENKINS_EXAMPLE:-false})"
      return 0
      ;;
  esac

  local template
  template="$(cat "${ROOT_DIR}/templates/jenkins-example.Jenkinsfile")"
  local prod_jenkinsfile="${template//__HELLO_MESSAGE__/hello prod world}"
  local dev_jenkinsfile="${template//__HELLO_MESSAGE__/hello dev world}"

  ensure_repo_with_branch_jenkinsfiles \
    "${GITEA_JENKINS_EXAMPLE_REPO:-jenkins-example}" \
    "$prod_jenkinsfile" \
    "$dev_jenkinsfile" \
    "Jenkins example"
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
}
