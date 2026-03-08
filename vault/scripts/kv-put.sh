#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CREDS_FILE="${SCRIPT_DIR}/../.vault/credentials.env"
VAULT_KV_MOUNT="${VAULT_KV_MOUNT:-secret}"
VAULT_CREDS_FILE="${VAULT_CREDS_FILE:-$DEFAULT_CREDS_FILE}"

usage() {
  echo "Usage: $0 <path> <key> <value> [<key> <value> ...]" >&2
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

build_pairs_json() {
  if (( $# == 0 || $# % 2 != 0 )); then
    return 1
  fi

  local out=""
  local key value escaped_key escaped_value
  while (( $# > 0 )); do
    key="$1"
    value="$2"
    shift 2
    escaped_key="$(json_escape "$key")"
    escaped_value="$(json_escape "$value")"
    if [[ -n "$out" ]]; then
      out+=","
    fi
    out+="\"${escaped_key}\":\"${escaped_value}\""
  done

  printf '{%s}' "$out"
}

write_v2() {
  local addr="$1"
  local token="$2"
  local path="$3"
  local data_json="$4"
  local body_file
  local status

  body_file="$(mktemp)"
  status="$(
    curl -sS -o "${body_file}" -w "%{http_code}" \
      --request POST \
      --header "X-Vault-Token: ${token}" \
      --header "Content-Type: application/json" \
      --data "{\"data\":${data_json}}" \
      "${addr%/}/v1/${VAULT_KV_MOUNT}/data/${path}" || true
  )"

  if [[ "${status}" =~ ^2[0-9][0-9]$ ]]; then
    rm -f "${body_file}"
    return 0
  fi

  rm -f "${body_file}"
  return 1
}

write_v1() {
  local addr="$1"
  local token="$2"
  local path="$3"
  local data_json="$4"
  local body_file
  local status

  body_file="$(mktemp)"
  status="$(
    curl -sS -o "${body_file}" -w "%{http_code}" \
      --request POST \
      --header "X-Vault-Token: ${token}" \
      --header "Content-Type: application/json" \
      --data "${data_json}" \
      "${addr%/}/v1/${VAULT_KV_MOUNT}/${path}" || true
  )"

  if [[ "${status}" =~ ^2[0-9][0-9]$ ]]; then
    rm -f "${body_file}"
    return 0
  fi

  rm -f "${body_file}"
  return 1
}

if (( $# < 3 )); then
  usage
  exit 2
fi

if (( ($# - 1) % 2 != 0 )); then
  usage
  exit 2
fi

secret_path="$1"
shift

if [[ -f "${VAULT_CREDS_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${VAULT_CREDS_FILE}"
  set +a
fi

vault_addr="${VAULT_ADDR:-http://127.0.0.1:8200}"
vault_token="${VAULT_TOKEN:-${VAULT_ROOT_TOKEN:-}}"

if [[ -z "${vault_token}" ]]; then
  echo "Vault token not available (set VAULT_TOKEN or ensure ${VAULT_CREDS_FILE} has VAULT_ROOT_TOKEN)." >&2
  exit 1
fi

if ! curl -fsS --connect-timeout 2 --max-time 4 "${vault_addr%/}/v1/sys/health" >/dev/null 2>&1; then
  echo "Vault API not reachable at ${vault_addr}" >&2
  exit 1
fi

pairs_json="$(build_pairs_json "$@")"

if write_v2 "${vault_addr}" "${vault_token}" "${secret_path}" "${pairs_json}"; then
  echo "Stored secret at ${VAULT_KV_MOUNT}/data/${secret_path}"
  exit 0
fi

if write_v1 "${vault_addr}" "${vault_token}" "${secret_path}" "${pairs_json}"; then
  echo "Stored secret at ${VAULT_KV_MOUNT}/${secret_path}"
  exit 0
fi

echo "Failed to store secret at ${secret_path} in mount ${VAULT_KV_MOUNT}" >&2
exit 1
