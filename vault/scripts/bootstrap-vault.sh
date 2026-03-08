#!/usr/bin/env bash
set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
CREDS_FILE="${CREDS_FILE:-./.vault/credentials.env}"
BOOTSTRAP_TIMEOUT="${BOOTSTRAP_TIMEOUT:-60}"
VAULT_ADMIN_USERNAME="${VAULT_ADMIN_USERNAME:-admin}"
VAULT_ADMIN_PASSWORD="${VAULT_ADMIN_PASSWORD:-password}"
VAULT_USER_USERNAME="${VAULT_USER_USERNAME:-user}"
VAULT_USER_PASSWORD="${VAULT_USER_PASSWORD:-password}"
VAULT_ADMIN_POLICY_NAME="${VAULT_ADMIN_POLICY_NAME:-vault-admin}"

wait_for_vault_api() {
  local attempt code
  for attempt in $(seq 1 "$BOOTSTRAP_TIMEOUT"); do
    code="$(curl -s -o /dev/null -w "%{http_code}" "${VAULT_ADDR}/v1/sys/health" 2>/dev/null || true)"
    if [[ -n "$code" && "$code" != "000" ]]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

is_initialized() {
  local payload
  payload="$(curl -sS "${VAULT_ADDR}/v1/sys/init")"
  grep -q '"initialized"[[:space:]]*:[[:space:]]*true' <<<"$payload"
}

is_sealed() {
  local payload
  payload="$(curl -sS "${VAULT_ADDR}/v1/sys/seal-status")"
  grep -q '"sealed"[[:space:]]*:[[:space:]]*true' <<<"$payload"
}

extract_json_string() {
  local payload="$1"
  local key="$2"
  sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" <<<"$payload"
}

extract_first_array_string() {
  local payload="$1"
  local key="$2"
  sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\\[[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" <<<"$payload"
}

has_secret_mount() {
  local mounts
  mounts="$(curl -sS --header "X-Vault-Token: ${VAULT_ROOT_TOKEN}" "${VAULT_ADDR}/v1/sys/mounts" || true)"
  grep -q '"secret/"' <<<"$mounts"
}

enable_secret_kv_mount() {
  curl -sS --request POST \
    --header "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
    --header "Content-Type: application/json" \
    --data '{"type":"kv","options":{"version":"2"},"description":"KV v2 for local service credentials"}' \
    "${VAULT_ADDR}/v1/sys/mounts/secret" >/dev/null
}

ensure_secret_kv_mount() {
  if [[ -z "${VAULT_ROOT_TOKEN:-}" ]]; then
    echo "Cannot ensure secret KV mount: VAULT_ROOT_TOKEN is not set."
    return 1
  fi

  if has_secret_mount; then
    return 0
  fi

  if enable_secret_kv_mount; then
    echo "Enabled Vault KV v2 mount at secret/"
    return 0
  fi

  echo "Failed to enable Vault KV mount at secret/"
  return 1
}

has_userpass_auth() {
  local auths
  auths="$(curl -sS --header "X-Vault-Token: ${VAULT_ROOT_TOKEN}" "${VAULT_ADDR}/v1/sys/auth" || true)"
  grep -q '"userpass/"' <<<"$auths"
}

enable_userpass_auth() {
  curl -sS --request POST \
    --header "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
    --header "Content-Type: application/json" \
    --data '{"type":"userpass","description":"Username/password auth for local users"}' \
    "${VAULT_ADDR}/v1/sys/auth/userpass" >/dev/null
}

ensure_userpass_auth() {
  if [[ -z "${VAULT_ROOT_TOKEN:-}" ]]; then
    echo "Cannot ensure userpass auth: VAULT_ROOT_TOKEN is not set."
    return 1
  fi

  if has_userpass_auth; then
    return 0
  fi

  if enable_userpass_auth; then
    echo "Enabled Vault userpass auth at auth/userpass"
    return 0
  fi

  echo "Failed to enable Vault userpass auth"
  return 1
}

upsert_userpass_user() {
  local username="$1"
  local password="$2"
  local policies="$3"

  curl -sS --request POST \
    --header "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
    --header "Content-Type: application/json" \
    --data "$(printf '{"password":"%s","policies":"%s"}' "$password" "$policies")" \
    "${VAULT_ADDR}/v1/auth/userpass/users/${username}" >/dev/null
}

upsert_admin_policy() {
  curl -sS --request PUT \
    --header "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
    --header "Content-Type: application/json" \
    --data '{"policy":"path \"*\" { capabilities = [\"create\", \"read\", \"update\", \"delete\", \"list\", \"sudo\", \"patch\"] }"}' \
    "${VAULT_ADDR}/v1/sys/policies/acl/${VAULT_ADMIN_POLICY_NAME}" >/dev/null
}

ensure_default_users() {
  if [[ -z "${VAULT_ROOT_TOKEN:-}" ]]; then
    echo "Cannot ensure default users: VAULT_ROOT_TOKEN is not set."
    return 1
  fi

  ensure_userpass_auth

  if upsert_admin_policy; then
    echo "Configured admin policy: ${VAULT_ADMIN_POLICY_NAME}"
  else
    echo "Failed to configure admin policy: ${VAULT_ADMIN_POLICY_NAME}"
    return 1
  fi

  if upsert_userpass_user "$VAULT_ADMIN_USERNAME" "$VAULT_ADMIN_PASSWORD" "$VAULT_ADMIN_POLICY_NAME"; then
    echo "Configured admin user: ${VAULT_ADMIN_USERNAME}"
  else
    echo "Failed to configure admin user: ${VAULT_ADMIN_USERNAME}"
    return 1
  fi

  if upsert_userpass_user "$VAULT_USER_USERNAME" "$VAULT_USER_PASSWORD" "default"; then
    echo "Configured regular user: ${VAULT_USER_USERNAME}"
  else
    echo "Failed to configure regular user: ${VAULT_USER_USERNAME}"
    return 1
  fi
}

write_credentials_file() {
  local unseal_key="$1"
  local root_token="$2"
  local tmp_file

  mkdir -p "$(dirname "$CREDS_FILE")"
  tmp_file="${CREDS_FILE}.tmp"
  {
    printf 'VAULT_ADDR=%q\n' "$VAULT_ADDR"
    printf 'VAULT_UNSEAL_KEY=%q\n' "$unseal_key"
    printf 'VAULT_ROOT_TOKEN=%q\n' "$root_token"
  } >"$tmp_file"
  chmod 600 "$tmp_file"
  mv "$tmp_file" "$CREDS_FILE"
}

if ! wait_for_vault_api; then
  echo "Vault API did not become reachable at ${VAULT_ADDR} within ${BOOTSTRAP_TIMEOUT}s"
  exit 1
fi

if ! is_initialized; then
  init_payload="$(curl -sS --request PUT --data '{"secret_shares":1,"secret_threshold":1}' "${VAULT_ADDR}/v1/sys/init")"
  init_payload="$(tr -d '\r\n\t' <<<"$init_payload")"

  unseal_key="$(extract_first_array_string "$init_payload" "keys_base64")"
  if [[ -z "$unseal_key" ]]; then
    unseal_key="$(extract_first_array_string "$init_payload" "keys")"
  fi
  root_token="$(extract_json_string "$init_payload" "root_token")"

  if [[ -z "$unseal_key" || -z "$root_token" ]]; then
    echo "Failed to parse Vault initialization payload."
    echo "$init_payload"
    exit 1
  fi

  write_credentials_file "$unseal_key" "$root_token"

  echo "Generated Vault credentials:"
  echo "  Unseal Key: $unseal_key"
  echo "  Root Token: $root_token"
  echo "Saved credentials to ${CREDS_FILE}"
fi

if [[ -f "$CREDS_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$CREDS_FILE"
  set +a
fi

if is_sealed; then
  if [[ -z "${VAULT_UNSEAL_KEY:-}" ]]; then
    echo "Vault is sealed but no unseal key is available at ${CREDS_FILE}"
    exit 1
  fi

  curl -sS --request PUT --data "$(printf '{"key":"%s"}' "$VAULT_UNSEAL_KEY")" \
    "${VAULT_ADDR}/v1/sys/unseal" >/dev/null
fi

for _ in $(seq 1 15); do
  if ! is_sealed; then
    break
  fi
  sleep 1
done

if is_sealed; then
  echo "Vault is still sealed after automatic unseal attempt."
  exit 1
fi

echo "Vault is initialized and unsealed at ${VAULT_ADDR}"
if [[ -n "${VAULT_ROOT_TOKEN:-}" ]]; then
  ensure_secret_kv_mount
  ensure_default_users
  echo "Root Token: ${VAULT_ROOT_TOKEN}"
  echo "Login: vault login ${VAULT_ROOT_TOKEN}"
  echo "Admin login: vault login -method=userpass username=${VAULT_ADMIN_USERNAME} password=${VAULT_ADMIN_PASSWORD}"
  echo "User login: vault login -method=userpass username=${VAULT_USER_USERNAME} password=${VAULT_USER_PASSWORD}"
fi
