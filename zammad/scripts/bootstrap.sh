#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-.env}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(cd "${SERVICE_DIR}/.." && pwd)"
COMPOSE_FILE="${SERVICE_DIR}/docker-compose.yml"
VAULT_HELPER="${ROOT_DIR}/vault/scripts/kv-put.sh"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing env file: ${ENV_FILE}" >&2
  exit 1
fi

compose() {
  docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" "$@"
}

load_env() {
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]]; then
      continue
    fi

    local key="${line%%=*}"
    local value="${line#*=}"

    if [[ "${value}" =~ ^\".*\"$ || "${value}" =~ ^\'.*\'$ ]]; then
      value="${value:1:${#value}-2}"
    fi

    export "${key}=${value}"
  done <"${ENV_FILE}"
}

random_secret() {
  local length="${1:-32}"
  (
    set +o pipefail
    LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${length}"
  )
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

set_env_var() {
  local key="$1"
  local value="$2"
  local escaped
  escaped="$(escape_sed_replacement "${value}")"

  if grep -q "^${key}=" "${ENV_FILE}"; then
    sed -i.bak "s/^${key}=.*/${key}=${escaped}/" "${ENV_FILE}"
  else
    printf '%s=%s\n' "${key}" "${value}" >>"${ENV_FILE}"
  fi

  rm -f "${ENV_FILE}.bak"
}

build_autowizard_json() {
  python3 - <<'PY'
import base64
import json
import os

payload = {
    "Token": os.environ["ZAMMAD_AUTOWIZARD_TOKEN"],
    "TextModuleLocale": {"Locale": "en-us"},
    "Users": [
        {
            "login": os.environ["ZAMMAD_ADMIN_EMAIL"],
            "firstname": os.environ["ZAMMAD_ADMIN_FIRSTNAME"],
            "lastname": os.environ["ZAMMAD_ADMIN_LASTNAME"],
            "email": os.environ["ZAMMAD_ADMIN_EMAIL"],
            "organization": os.environ["ZAMMAD_ORGANIZATION"],
            "password": os.environ["ZAMMAD_ADMIN_PASSWORD"],
        }
    ],
    "Settings": [
        {"name": "product_name", "value": os.environ["ZAMMAD_PRODUCT_NAME"]},
        {"name": "system_online_service", "value": True},
    ],
    "Organizations": [
        {"name": os.environ["ZAMMAD_ORGANIZATION"]},
    ],
}

encoded = base64.b64encode(
    json.dumps(payload, separators=(",", ":")).encode("utf-8")
).decode("ascii")
print(encoded)
PY
}

ensure_required_env() {
  load_env

  : "${ZAMMAD_PORT:=8090}"
  : "${ZAMMAD_URL:=http://127.0.0.1:${ZAMMAD_PORT}}"
  : "${NGINX_PORT:=8080}"
  : "${NGINX_EXPOSE_PORT:=${ZAMMAD_PORT}}"
  : "${ZAMMAD_FQDN:=localhost}"
  : "${ZAMMAD_HTTP_TYPE:=http}"
  : "${ZAMMAD_ADMIN_EMAIL:=admin@zammad.local}"
  : "${ZAMMAD_ADMIN_FIRSTNAME:=Playground}"
  : "${ZAMMAD_ADMIN_LASTNAME:=Admin}"
  : "${ZAMMAD_ORGANIZATION:=Playground Zammad}"
  : "${ZAMMAD_PRODUCT_NAME:=Playground Zammad}"
  : "${POSTGRES_DB:=zammad_production}"
  : "${POSTGRES_USER:=zammad}"
  : "${ELASTICSEARCH_USER:=elastic}"

  if [[ -z "${POSTGRES_PASS:-}" ]]; then
    POSTGRES_PASS="$(random_secret 28)"
    set_env_var POSTGRES_PASS "${POSTGRES_PASS}"
  fi

  if [[ -z "${ELASTICSEARCH_PASS:-}" ]]; then
    ELASTICSEARCH_PASS="$(random_secret 28)"
    set_env_var ELASTICSEARCH_PASS "${ELASTICSEARCH_PASS}"
  fi

  if [[ -z "${ZAMMAD_ADMIN_PASSWORD:-}" ]]; then
    ZAMMAD_ADMIN_PASSWORD="Play${RANDOM}Ground$(random_secret 14)"
    set_env_var ZAMMAD_ADMIN_PASSWORD "${ZAMMAD_ADMIN_PASSWORD}"
  fi

  if [[ -z "${ZAMMAD_AUTOWIZARD_TOKEN:-}" ]]; then
    ZAMMAD_AUTOWIZARD_TOKEN="$(random_secret 96)"
    set_env_var ZAMMAD_AUTOWIZARD_TOKEN "${ZAMMAD_AUTOWIZARD_TOKEN}"
  fi

  set_env_var ZAMMAD_PORT "${ZAMMAD_PORT}"
  set_env_var ZAMMAD_URL "${ZAMMAD_URL}"
  set_env_var NGINX_PORT "${NGINX_PORT}"
  set_env_var NGINX_EXPOSE_PORT "${NGINX_EXPOSE_PORT}"
  set_env_var ZAMMAD_FQDN "${ZAMMAD_FQDN}"
  set_env_var ZAMMAD_HTTP_TYPE "${ZAMMAD_HTTP_TYPE}"
  set_env_var ZAMMAD_ADMIN_EMAIL "${ZAMMAD_ADMIN_EMAIL}"
  set_env_var ZAMMAD_ADMIN_FIRSTNAME "${ZAMMAD_ADMIN_FIRSTNAME}"
  set_env_var ZAMMAD_ADMIN_LASTNAME "${ZAMMAD_ADMIN_LASTNAME}"
  set_env_var ZAMMAD_ORGANIZATION "${ZAMMAD_ORGANIZATION}"
  set_env_var ZAMMAD_PRODUCT_NAME "${ZAMMAD_PRODUCT_NAME}"

  load_env
  AUTOWIZARD_JSON="$(build_autowizard_json)"
  set_env_var AUTOWIZARD_JSON "${AUTOWIZARD_JSON}"
  load_env
}

wait_for_http() {
  local url="${1}"
  local attempts="${2:-180}"
  local delay="${3:-5}"
  local code=""

  echo "Waiting for Zammad at ${url}"

  for ((i = 1; i <= attempts; i++)); do
    code="$(
      curl -sS -o /dev/null -w '%{http_code}' \
        --connect-timeout 3 \
        --max-time 8 \
        "${url}" 2>/dev/null || true
    )"

    if [[ "${code}" == "200" || "${code}" == "302" ]]; then
      echo "Zammad is responding at ${url} (${code})"
      return 0
    fi

    if [[ "${i}" -eq 1 || $((i % 6)) -eq 0 ]]; then
      echo "  still waiting... attempt ${i}/${attempts} (last code: ${code:-none})"
    fi

    sleep "${delay}"
  done

  echo "Zammad did not become ready in time at ${url}" >&2
  return 1
}

wait_for_init_complete() {
  local attempts="${1:-180}"
  local delay="${2:-5}"
  local output=""

  echo "Waiting for zammad-init to finish"

  for ((i = 1; i <= attempts; i++)); do
    output="$(docker inspect playground-zammad-init --format '{{.State.Status}} {{.State.ExitCode}}' 2>/dev/null || true)"

    if [[ "${output}" == "exited 0" ]]; then
      echo "zammad-init finished successfully"
      return 0
    fi

    if [[ "${i}" -eq 1 || $((i % 6)) -eq 0 ]]; then
      echo "  still waiting for zammad-init... attempt ${i}/${attempts} (state: ${output:-missing})"
    fi

    sleep "${delay}"
  done

  echo "zammad-init did not finish successfully in time." >&2
  return 1
}

install_autowizard_file() {
  local container_path=""
  local relative_dir=""
  local output=""

  container_path="$(
    compose exec -T zammad-railsserver \
      bundle exec rails r \
      "puts AutoWizard.send(:file_location).to_s" \
      2>/dev/null | tail -n 1 | tr -d '\r'
  )"

  if [[ -z "${container_path}" || "${container_path}" != /opt/zammad/* ]]; then
    echo "Could not determine autowizard file path inside zammad-railsserver." >&2
    return 1
  fi

  relative_dir="$(dirname "${container_path}")"

  echo "Installing autowizard payload into zammad-railsserver:${container_path}"

  if ! compose exec -T zammad-railsserver sh -lc "mkdir -p '${relative_dir}' && cat > '${container_path}'" \
    <<<"$(printf '%s' "${AUTOWIZARD_JSON}" | base64 -d)"; then
    echo "Failed to write autowizard payload into zammad-railsserver." >&2
    return 1
  fi

  output="$(
    compose exec -T zammad-railsserver \
    bundle exec rails r \
    "puts AutoWizard.enabled? ? 'enabled' : 'disabled'" \
    2>/dev/null || true
  )"

  if ! printf '%s\n' "${output}" | tr -d '\r' | grep -q '^enabled$'; then
    echo "Autowizard payload is still not visible inside zammad-railsserver." >&2
    return 1
  fi
}

admin_user_exists() {
  local output
  output="$(
    compose exec -T zammad-railsserver \
    bundle exec rails r \
    "u = User.find_by(email: '${ZAMMAD_ADMIN_EMAIL}'); puts(u ? 'present' : 'missing')" \
    2>/dev/null || true
  )"
  printf '%s\n' "${output}" | tr -d '\r' | grep -q '^present$'
}

run_autowizard() {
  local wizard_url="${ZAMMAD_URL%/}/api/v1/getting_started/auto_wizard/${ZAMMAD_AUTOWIZARD_TOKEN}"
  local response_file status

  response_file="$(mktemp)"
  status="$(
    curl -sS -o "${response_file}" -w '%{http_code}' \
      --connect-timeout 3 \
      --max-time 30 \
      "${wizard_url}" || true
  )"

  if [[ "${status}" != "200" ]]; then
    echo "Autowizard request failed (HTTP ${status})." >&2
    cat "${response_file}" >&2 || true
    rm -f "${response_file}"
    return 1
  fi

  if ! grep -q '"auto_wizard_success":true' "${response_file}"; then
    echo "Autowizard request did not report success." >&2
    cat "${response_file}" >&2 || true
    rm -f "${response_file}"
    return 1
  fi

  rm -f "${response_file}"
}

wait_for_admin_user() {
  local attempts="${1:-60}"
  local delay="${2:-5}"

  for ((i = 1; i <= attempts; i++)); do
    if admin_user_exists; then
      return 0
    fi

    if [[ "${i}" -eq 1 || $((i % 6)) -eq 0 ]]; then
      echo "  waiting for autowizard-created admin user... attempt ${i}/${attempts}"
    fi

    sleep "${delay}"
  done

  echo "Admin user ${ZAMMAD_ADMIN_EMAIL} was not created in time." >&2
  return 1
}

sync_credentials_to_vault() {
  if [[ ! -x "${VAULT_HELPER}" ]]; then
    echo "Vault sync skipped: helper not found at ${VAULT_HELPER}"
    return 0
  fi

  if ! "${VAULT_HELPER}" "services/zammad" \
    "url" "${ZAMMAD_URL}" \
    "admin_user" "${ZAMMAD_ADMIN_EMAIL}" \
    "admin_password" "${ZAMMAD_ADMIN_PASSWORD}" \
    "admin_firstname" "${ZAMMAD_ADMIN_FIRSTNAME}" \
    "admin_lastname" "${ZAMMAD_ADMIN_LASTNAME}" \
    "organization" "${ZAMMAD_ORGANIZATION}" \
    "autowizard_token" "${ZAMMAD_AUTOWIZARD_TOKEN}" \
    "postgres_db" "${POSTGRES_DB}" \
    "postgres_user" "${POSTGRES_USER}" \
    "postgres_password" "${POSTGRES_PASS}" \
    "elasticsearch_user" "${ELASTICSEARCH_USER}" \
    "elasticsearch_password" "${ELASTICSEARCH_PASS}"; then
    echo "Warning: failed to sync Zammad credentials to Vault." >&2
  fi
}

print_summary() {
  cat <<EOF

Zammad is ready.
URL: ${ZAMMAD_URL}
Admin login: ${ZAMMAD_ADMIN_EMAIL}
Admin password: ${ZAMMAD_ADMIN_PASSWORD}
Vault secret: secret/data/services/zammad
EOF
}

ensure_required_env
compose up -d
wait_for_http "${ZAMMAD_URL}"
wait_for_init_complete
if admin_user_exists; then
  echo "Admin user ${ZAMMAD_ADMIN_EMAIL} already exists. Skipping autowizard."
else
  install_autowizard_file
  run_autowizard
  wait_for_admin_user
fi
sync_credentials_to_vault
print_summary
