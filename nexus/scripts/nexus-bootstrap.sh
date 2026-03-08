#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

NEXUS_URL="${NEXUS_URL:-http://localhost:8083}"
NEXUS_DATA_DIR="${NEXUS_DATA_DIR:?NEXUS_DATA_DIR is required}"
NEXUS_BOOTSTRAP_USER="${NEXUS_BOOTSTRAP_USER:-admin}"
NEXUS_BOOTSTRAP_PASSWORD="${NEXUS_BOOTSTRAP_PASSWORD:-}"
NEXUS_ADMIN_USER="${NEXUS_ADMIN_USER:-admin}"
NEXUS_ADMIN_PASSWORD="${NEXUS_ADMIN_PASSWORD:-password}"
NEXUS_REGULAR_USER="${NEXUS_REGULAR_USER:-user}"
NEXUS_REGULAR_PASSWORD="${NEXUS_REGULAR_PASSWORD:-password}"
NEXUS_ANONYMOUS_ENABLED="${NEXUS_ANONYMOUS_ENABLED:-false}"
NEXUS_WAIT_TIMEOUT="${NEXUS_WAIT_TIMEOUT:-600}"
NEXUS_WAIT_INTERVAL="${NEXUS_WAIT_INTERVAL:-5}"
NEXUS_BOOTSTRAP_PASSWORD_FILE="${NEXUS_BOOTSTRAP_PASSWORD_FILE:-$NEXUS_DATA_DIR/.nexus-admin-password}"
NEXUS_CONNECT_TIMEOUT="${NEXUS_CONNECT_TIMEOUT:-2}"
NEXUS_CURL_MAX_TIME="${NEXUS_CURL_MAX_TIME:-5}"

log() {
  echo "[nexus-bootstrap] $*"
}

normalize_bool() {
  local value="${1:-}"
  case "$value" in
    true|TRUE|True|1|yes|YES|Yes|on|ON|On) echo "true" ;;
    false|FALSE|False|0|no|NO|No|off|OFF|Off) echo "false" ;;
    *)
      echo "Unsupported boolean value '${value}' (expected true/false)." >&2
      exit 1
      ;;
  esac
}

add_candidate() {
  local candidate="$1"
  [[ -n "$candidate" ]] || return 0
  for existing in "${password_candidates[@]:-}"; do
    [[ "$existing" == "$candidate" ]] && return 0
  done
  password_candidates+=("$candidate")
}

check_bootstrap_auth() {
  local password="$1"
  local status
  status="$(curl -s -o /dev/null -w '%{http_code}' \
    --connect-timeout "$NEXUS_CONNECT_TIMEOUT" \
    --max-time "$NEXUS_CURL_MAX_TIME" \
    -u "${NEXUS_BOOTSTRAP_USER}:${password}" \
    "${NEXUS_URL}/service/rest/v1/security/users" || true)"
  [[ "$status" == "200" ]]
}

try_change_bootstrap_password() {
  local current_password="$1"
  local new_password="$2"
  local status

  status="$(curl -s -o /dev/null -w '%{http_code}' \
    --connect-timeout "$NEXUS_CONNECT_TIMEOUT" \
    --max-time "$NEXUS_CURL_MAX_TIME" \
    -u "${NEXUS_BOOTSTRAP_USER}:${current_password}" \
    -H "Content-Type: text/plain" \
    -X PUT \
    --data "$new_password" \
    "${NEXUS_URL}/service/rest/v1/security/users/${NEXUS_BOOTSTRAP_USER}/change-password" || true)"

  [[ "$status" == "200" || "$status" == "204" ]]
}

wait_for_nexus_status() {
  local start now elapsed attempts
  start="$(date +%s)"
  attempts=0
  while true; do
    if curl -fsS \
      --connect-timeout "$NEXUS_CONNECT_TIMEOUT" \
      --max-time "$NEXUS_CURL_MAX_TIME" \
      "${NEXUS_URL}/service/rest/v1/status" >/dev/null 2>&1; then
      log "Nexus status endpoint is ready."
      return 0
    fi

    attempts=$((attempts + 1))
    now="$(date +%s)"
    elapsed=$((now - start))
    if (( attempts == 1 || attempts % 3 == 0 )); then
      log "Waiting for Nexus API at ${NEXUS_URL} (${elapsed}s elapsed, timeout ${NEXUS_WAIT_TIMEOUT}s)."
    fi
    if (( now - start >= NEXUS_WAIT_TIMEOUT )); then
      echo "Timed out waiting for Nexus status endpoint at ${NEXUS_URL}" >&2
      echo "Try: make up MODE=<docker|bare> NEXUS_AUTO_INIT=false (skip bootstrap) and inspect logs." >&2
      exit 1
    fi
    sleep "$NEXUS_WAIT_INTERVAL"
  done
}

wait_for_bootstrap_password() {
  local start now elapsed attempts file_password candidate
  start="$(date +%s)"
  attempts=0
  while true; do
    attempts=$((attempts + 1))
    password_candidates=()
    add_candidate "$NEXUS_BOOTSTRAP_PASSWORD"
    add_candidate "$NEXUS_ADMIN_PASSWORD"
    if [[ -f "$NEXUS_BOOTSTRAP_PASSWORD_FILE" ]]; then
      add_candidate "$(tr -d '\r\n' <"$NEXUS_BOOTSTRAP_PASSWORD_FILE")"
    fi
    if [[ -f "$NEXUS_DATA_DIR/admin.password" ]]; then
      file_password="$(tr -d '\r\n' <"$NEXUS_DATA_DIR/admin.password")"
      add_candidate "$file_password"
      if [[ -n "$NEXUS_BOOTSTRAP_PASSWORD" ]] \
        && [[ "$file_password" != "$NEXUS_BOOTSTRAP_PASSWORD" ]] \
        && try_change_bootstrap_password "$file_password" "$NEXUS_BOOTSTRAP_PASSWORD"; then
        CURRENT_BOOTSTRAP_PASSWORD="$NEXUS_BOOTSTRAP_PASSWORD"
        log "Bootstrap password configured from admin.password bootstrap secret."
        return 0
      fi
    fi
    add_candidate "admin123"
    add_candidate "nexus-admin"

    for candidate in "${password_candidates[@]}"; do
      if check_bootstrap_auth "$candidate"; then
        CURRENT_BOOTSTRAP_PASSWORD="$candidate"
        log "Bootstrap authentication succeeded."
        return 0
      fi
    done

    now="$(date +%s)"
    elapsed=$((now - start))
    if (( attempts == 1 || attempts % 3 == 0 )); then
      log "Waiting for bootstrap authentication (${elapsed}s elapsed, timeout ${NEXUS_WAIT_TIMEOUT}s)."
      if [[ ! -f "$NEXUS_DATA_DIR/admin.password" ]]; then
        log "admin.password not present yet: ${NEXUS_DATA_DIR}/admin.password"
      fi
    fi
    if (( now - start >= NEXUS_WAIT_TIMEOUT )); then
      echo "Timed out authenticating bootstrap user at ${NEXUS_URL}" >&2
      echo "Tried passwords from:"
      echo "  - NEXUS_BOOTSTRAP_PASSWORD"
      echo "  - ${NEXUS_BOOTSTRAP_PASSWORD_FILE}"
      echo "  - ${NEXUS_DATA_DIR}/admin.password"
      echo "  - admin123"
      echo "Try: make up MODE=<docker|bare> NEXUS_AUTO_INIT=false (skip bootstrap) and inspect logs." >&2
      exit 1
    fi
    sleep "$NEXUS_WAIT_INTERVAL"
  done
}

configure_bootstrap_password() {
  if [[ "$CURRENT_BOOTSTRAP_PASSWORD" == "$NEXUS_BOOTSTRAP_PASSWORD" ]]; then
    return 0
  fi

  if ! try_change_bootstrap_password "$CURRENT_BOOTSTRAP_PASSWORD" "$NEXUS_BOOTSTRAP_PASSWORD"; then
    echo "Failed to update bootstrap password via Nexus API." >&2
    exit 1
  fi

  CURRENT_BOOTSTRAP_PASSWORD="$NEXUS_BOOTSTRAP_PASSWORD"
}

user_exists() {
  local user_id="$1"
  local users
  users="$(curl -sS \
    --connect-timeout "$NEXUS_CONNECT_TIMEOUT" \
    --max-time "$NEXUS_CURL_MAX_TIME" \
    -u "${NEXUS_BOOTSTRAP_USER}:${CURRENT_BOOTSTRAP_PASSWORD}" \
    "${NEXUS_URL}/service/rest/v1/security/users" || true)"
  grep -q "\"userId\"[[:space:]]*:[[:space:]]*\"${user_id}\"" <<<"$users"
}

set_user_password() {
  local user_id="$1"
  local password="$2"
  local status

  status="$(curl -s -o /dev/null -w '%{http_code}' \
    --connect-timeout "$NEXUS_CONNECT_TIMEOUT" \
    --max-time "$NEXUS_CURL_MAX_TIME" \
    -u "${NEXUS_BOOTSTRAP_USER}:${CURRENT_BOOTSTRAP_PASSWORD}" \
    -H "Content-Type: text/plain" \
    -X PUT \
    --data "$password" \
    "${NEXUS_URL}/service/rest/v1/security/users/${user_id}/change-password" || true)"

  if [[ "$status" != "200" && "$status" != "204" ]]; then
    echo "Failed to set password for user '${user_id}'." >&2
    exit 1
  fi

  if [[ "$user_id" == "$NEXUS_BOOTSTRAP_USER" ]]; then
    CURRENT_BOOTSTRAP_PASSWORD="$password"
  fi
}

upsert_user() {
  local user_id="$1"
  local password="$2"
  local first_name="$3"
  local last_name="$4"
  local email="$5"
  local roles_json="$6"
  local status

  if user_exists "$user_id"; then
    status="$(curl -s -o /dev/null -w '%{http_code}' \
      --connect-timeout "$NEXUS_CONNECT_TIMEOUT" \
      --max-time "$NEXUS_CURL_MAX_TIME" \
      -u "${NEXUS_BOOTSTRAP_USER}:${CURRENT_BOOTSTRAP_PASSWORD}" \
      -H "Content-Type: application/json" \
      -X PUT \
      --data "{\"userId\":\"${user_id}\",\"firstName\":\"${first_name}\",\"lastName\":\"${last_name}\",\"emailAddress\":\"${email}\",\"status\":\"active\",\"roles\":${roles_json},\"source\":\"default\"}" \
      "${NEXUS_URL}/service/rest/v1/security/users/${user_id}" || true)"
    if [[ "$status" != "200" && "$status" != "204" ]]; then
      echo "Failed to update user '${user_id}'." >&2
      exit 1
    fi
  else
    status="$(curl -s -o /dev/null -w '%{http_code}' \
      --connect-timeout "$NEXUS_CONNECT_TIMEOUT" \
      --max-time "$NEXUS_CURL_MAX_TIME" \
      -u "${NEXUS_BOOTSTRAP_USER}:${CURRENT_BOOTSTRAP_PASSWORD}" \
      -H "Content-Type: application/json" \
      -X POST \
      --data "{\"userId\":\"${user_id}\",\"firstName\":\"${first_name}\",\"lastName\":\"${last_name}\",\"emailAddress\":\"${email}\",\"password\":\"${password}\",\"status\":\"active\",\"roles\":${roles_json}}" \
      "${NEXUS_URL}/service/rest/v1/security/users" || true)"
    if [[ "$status" != "200" && "$status" != "204" ]]; then
      echo "Failed to create user '${user_id}'." >&2
      exit 1
    fi
  fi

  set_user_password "$user_id" "$password"
}

ensure_required_users() {
  upsert_user \
    "$NEXUS_ADMIN_USER" \
    "$NEXUS_ADMIN_PASSWORD" \
    "Nexus" \
    "Admin" \
    "admin@example.local" \
    '["nx-admin"]'

  if [[ "$NEXUS_REGULAR_USER" != "$NEXUS_ADMIN_USER" ]]; then
    upsert_user \
      "$NEXUS_REGULAR_USER" \
      "$NEXUS_REGULAR_PASSWORD" \
      "Nexus" \
      "User" \
      "user@example.local" \
      '["nx-anonymous"]'
  fi
}

configure_anonymous_access() {
  local enabled_json
  enabled_json="$(normalize_bool "$NEXUS_ANONYMOUS_ENABLED")"

  if ! curl -fsS \
    --connect-timeout "$NEXUS_CONNECT_TIMEOUT" \
    --max-time "$NEXUS_CURL_MAX_TIME" \
    -u "${NEXUS_BOOTSTRAP_USER}:${CURRENT_BOOTSTRAP_PASSWORD}" \
    -H "Content-Type: application/json" \
    -X PUT \
    --data "{\"enabled\":${enabled_json},\"userId\":\"anonymous\",\"realmName\":\"NexusAuthorizingRealm\"}" \
    "${NEXUS_URL}/service/rest/v1/security/anonymous" \
    >/dev/null; then
    echo "Warning: could not set anonymous access automatically; continuing."
  fi
}

persist_bootstrap_password() {
  mkdir -p "$(dirname "$NEXUS_BOOTSTRAP_PASSWORD_FILE")"
  printf '%s\n' "$CURRENT_BOOTSTRAP_PASSWORD" >"$NEXUS_BOOTSTRAP_PASSWORD_FILE"
  chmod 600 "$NEXUS_BOOTSTRAP_PASSWORD_FILE" 2>/dev/null || true
}

sync_credentials_to_vault() {
  local vault_helper="${REPO_ROOT}/vault/scripts/kv-put.sh"
  if [[ ! -x "$vault_helper" ]]; then
    log "Vault sync skipped: helper not found at ${vault_helper}"
    return 0
  fi

  if ! "$vault_helper" "services/nexus" \
    "url" "$NEXUS_URL" \
    "admin_user" "$NEXUS_ADMIN_USER" \
    "admin_password" "$NEXUS_ADMIN_PASSWORD" \
    "regular_user" "$NEXUS_REGULAR_USER" \
    "regular_password" "$NEXUS_REGULAR_PASSWORD" \
    "bootstrap_user" "$NEXUS_BOOTSTRAP_USER" \
    "bootstrap_password" "$CURRENT_BOOTSTRAP_PASSWORD" \
    "anonymous_enabled" "$(normalize_bool "$NEXUS_ANONYMOUS_ENABLED")"; then
    log "Warning: failed to sync Nexus credentials to Vault."
  fi
}

print_credentials() {
  echo
  echo "Nexus is initialized and ready."
  echo "URL: ${NEXUS_URL}"
  echo "Admin Username: ${NEXUS_ADMIN_USER}"
  echo "Admin Password: ${NEXUS_ADMIN_PASSWORD}"
  echo "User Username: ${NEXUS_REGULAR_USER}"
  echo "User Password: ${NEXUS_REGULAR_PASSWORD}"
  echo "Anonymous access: $(normalize_bool "$NEXUS_ANONYMOUS_ENABLED")"
}

CURRENT_BOOTSTRAP_PASSWORD=""
password_candidates=()

log "Bootstrap started for ${NEXUS_URL}."

if [[ -z "$NEXUS_BOOTSTRAP_PASSWORD" ]]; then
  NEXUS_BOOTSTRAP_PASSWORD="$NEXUS_ADMIN_PASSWORD"
fi

wait_for_nexus_status
wait_for_bootstrap_password
configure_bootstrap_password
ensure_required_users
configure_anonymous_access
persist_bootstrap_password
sync_credentials_to_vault
print_credentials
