#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/env.sh
source "${SCRIPT_DIR}/lib/env.sh"

TOKEN_NAME="${JENKINS_REGULAR_API_TOKEN_NAME:-jenkins-api-token}"
TOKEN_WAIT_TIMEOUT_SECONDS="${JENKINS_TOKEN_WAIT_TIMEOUT_SECONDS:-240}"

wait_for_controller() {
  local instance="$1"
  local base_url
  local elapsed=0

  base_url="$(instance_base_url "$instance")"

  until "$CURL_BIN" -fsSL -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" "${base_url}login" >/dev/null 2>&1; do
    sleep 2
    elapsed=$((elapsed + 2))
    if (( elapsed >= TOKEN_WAIT_TIMEOUT_SECONDS )); then
      echo "Timeout waiting for ${instance} controller at ${base_url}" >&2
      return 1
    fi
  done
}

groovy_escape_single_quoted() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\'/\\\'}"
  printf '%s' "$value"
}

json_get_string_field() {
  local json="$1"
  local field="$2"
  printf '%s' "$json" | sed -n "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p"
}

generate_token_for_instance() {
  local instance="$1"
  local base_url cookie_file crumb_json crumb_field crumb script response token
  local escaped_user escaped_token_name

  base_url="$(instance_base_url "$instance")"
  wait_for_controller "$instance"

  cookie_file="$(mktemp)"
  crumb_json="$("$CURL_BIN" -fsSL \
    -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
    -c "$cookie_file" -b "$cookie_file" \
    "${base_url}crumbIssuer/api/json")"

  crumb_field="$(json_get_string_field "$crumb_json" "crumbRequestField")"
  crumb="$(json_get_string_field "$crumb_json" "crumb")"
  if [[ -z "$crumb_field" || -z "$crumb" ]]; then
    rm -f "$cookie_file"
    echo "Failed to obtain Jenkins crumb for ${instance}" >&2
    return 1
  fi

  escaped_user="$(groovy_escape_single_quoted "$JENKINS_REGULAR_USER")"
  escaped_token_name="$(groovy_escape_single_quoted "$TOKEN_NAME")"

  script="$(cat <<GROOVY
import hudson.model.User
import jenkins.security.ApiTokenProperty

def username = '${escaped_user}'
def tokenName = '${escaped_token_name}'
def user = User.getById(username, false)
if (user == null) {
  throw new IllegalStateException("User not found: " + username)
}

def property = user.getProperty(ApiTokenProperty)
if (property == null) {
  throw new IllegalStateException("ApiTokenProperty missing for user: " + username)
}

def store = property.tokenStore
def existingTokens
try {
  existingTokens = store.getTokenListSortedByName()
} catch (Throwable ignored) {
  existingTokens = store.tokenList
}

existingTokens.findAll { it.name == tokenName }.each { token ->
  store.revokeToken(token.uuid)
}

def created = property.generateNewToken(tokenName)
user.save()
println(created.plainValue)
GROOVY
)"

  response="$("$CURL_BIN" -fsSL \
    -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
    -c "$cookie_file" -b "$cookie_file" \
    -H "${crumb_field}: ${crumb}" \
    --data-urlencode "script=${script}" \
    "${base_url}scriptText")"
  rm -f "$cookie_file"

  token="$(printf '%s\n' "$response" | awk 'NF { line=$0 } END { print line }' | tr -d '\r')"
  if [[ -z "$token" ]]; then
    echo "Token generation response was empty for ${instance}" >&2
    return 1
  fi

  printf '%s' "$token"
}

sync_tokens_to_vault() {
  local prod_token="$1"
  local dev_token="$2"
  local vault_helper="${ROOT_DIR}/../vault/scripts/kv-put.sh"

  if [[ ! -x "$vault_helper" ]]; then
    echo "Vault sync skipped: helper not found at ${vault_helper}"
    return 0
  fi

  if ! "$vault_helper" "services/jenkins" \
    "admin_user" "${JENKINS_ADMIN_USER}" \
    "admin_password" "${JENKINS_ADMIN_PASSWORD}" \
    "regular_user" "${JENKINS_REGULAR_USER}" \
    "regular_password" "${JENKINS_REGULAR_PASSWORD}" \
    "prod_url" "$(instance_base_url "prod")" \
    "dev_url" "$(instance_base_url "dev")" \
    "regular_api_token_name" "${TOKEN_NAME}" \
    "prod_regular_api_token" "${prod_token}" \
    "dev_regular_api_token" "${dev_token}"; then
    echo "Warning: failed to sync Jenkins API tokens to Vault."
  fi
}

ensure_admin_credentials
prod_token="$(generate_token_for_instance "prod")"
dev_token="$(generate_token_for_instance "dev")"
sync_tokens_to_vault "$prod_token" "$dev_token"

echo "Generated ${TOKEN_NAME} for ${JENKINS_REGULAR_USER} on prod and dev."
