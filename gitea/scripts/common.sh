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
    "admin_user" "$GITEA_ADMIN_USER" \
    "admin_email" "$GITEA_ADMIN_EMAIL" \
    "admin_password" "$GITEA_ADMIN_PASSWORD" \
    "user" "$GITEA_USER" \
    "user_email" "$GITEA_USER_EMAIL" \
    "user_password" "$GITEA_USER_PASSWORD" \
    "runner_registration_token" "$GITEA_RUNNER_TOKEN" \
    "secret_key" "$GITEA_SECRET_KEY" \
    "internal_token" "$GITEA_INTERNAL_TOKEN" \
    "jwt_secret" "$GITEA_JWT_SECRET"; then
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
  local explicit_runner_token=0
  if [[ -n "${GITEA_ADMIN_PASSWORD:-}" ]]; then
    explicit_admin_password=1
  fi
  if [[ -n "${GITEA_USER_PASSWORD:-}" ]]; then
    explicit_user_password=1
  fi
  if [[ -n "${GITEA_RUNNER_TOKEN:-}" ]]; then
    explicit_runner_token=1
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
    GITEA_USER="user"
  fi
  if [[ -z "${GITEA_USER_EMAIL:-}" ]]; then
    GITEA_USER_EMAIL="user@example.com"
  fi
  if [[ -z "${GITEA_USER_PASSWORD:-}" ]]; then
    GITEA_USER_PASSWORD="password"
  fi
  if [[ -z "${GITEA_RUNNER_TOKEN:-}" ]]; then
    from_file="$(envfile_get "$env_file" "GITEA_RUNNER_TOKEN" || true)"
    if [[ -n "$from_file" ]]; then
      GITEA_RUNNER_TOKEN="$from_file"
    else
      GITEA_RUNNER_TOKEN="$(random_string 48)"
      envfile_set "$env_file" "GITEA_RUNNER_TOKEN" "$GITEA_RUNNER_TOKEN"
      log "Generated runner registration token."
    fi
  fi

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
  export GITEA_RUNNER_TOKEN
  export GITEA_SECRET_KEY
  export GITEA_INTERNAL_TOKEN
  export GITEA_JWT_SECRET

  sync_credentials_to_vault

  if (( explicit_admin_password == 0 )); then
    log "Admin login username: ${GITEA_ADMIN_USER}"
    log "Admin login password: ${GITEA_ADMIN_PASSWORD}"
  fi
  if (( explicit_user_password == 0 )); then
    log "User login username: ${GITEA_USER}"
    log "User login password: ${GITEA_USER_PASSWORD}"
  fi
  if (( explicit_runner_token == 0 )); then
    log "Runner registration token: ${GITEA_RUNNER_TOKEN}"
  fi
  if (( explicit_admin_password == 0 || explicit_user_password == 0 || explicit_runner_token == 0 )); then
    log "Persisted bootstrap values in: ${env_file}"
  fi
}
