#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-.env}"
COMPOSE_FILE="docker/docker-compose.yml"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FORCED_GITLAB_EXTERNAL_URL="${GITLAB_EXTERNAL_URL:-}"
FORCED_GITLAB_HTTP_PORT="${GITLAB_HTTP_PORT:-}"
FORCED_GITLAB_SSH_PORT="${GITLAB_SSH_PORT:-}"
FORCED_RUNNER_GITLAB_URL="${RUNNER_GITLAB_URL:-}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing env file: ${ENV_FILE}"
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required but was not found in PATH"
  exit 1
fi

ROOT_PASSWORD_PLACEHOLDER="ChangeMeRootPass_123!"
GENERATED_ROOT_PASSWORD=""
GENERATED_RUNNER_1_TOKEN=""
GENERATED_RUNNER_2_TOKEN=""
GENERATED_REGISTRATION_TOKEN=""
LOGIN_ADMIN_USERNAME="admin"
LOGIN_REGULAR_USERNAME="user"

compose() {
  docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" "$@"
}

apply_forced_env_overrides() {
  if [[ -n "${FORCED_GITLAB_EXTERNAL_URL}" ]]; then
    GITLAB_EXTERNAL_URL="${FORCED_GITLAB_EXTERNAL_URL}"
    export GITLAB_EXTERNAL_URL
  fi
  if [[ -n "${FORCED_GITLAB_HTTP_PORT}" ]]; then
    GITLAB_HTTP_PORT="${FORCED_GITLAB_HTTP_PORT}"
    export GITLAB_HTTP_PORT
  fi
  if [[ -n "${FORCED_GITLAB_SSH_PORT}" ]]; then
    GITLAB_SSH_PORT="${FORCED_GITLAB_SSH_PORT}"
    export GITLAB_SSH_PORT
  fi
  if [[ -n "${FORCED_RUNNER_GITLAB_URL}" ]]; then
    RUNNER_GITLAB_URL="${FORCED_RUNNER_GITLAB_URL}"
    export RUNNER_GITLAB_URL
  fi
}

load_env() {
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
  apply_forced_env_overrides
}

random_secret() {
  local length="${1:-24}"
  (
    set +o pipefail
    LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${length}"
  )
}

set_env_var() {
  local key="$1"
  local value="$2"
  local tmp
  tmp="$(mktemp)"

  awk -v k="${key}" -v v="${value}" '
    BEGIN { replaced = 0 }
    $0 ~ "^" k "=" {
      print k "=" v
      replaced = 1
      next
    }
    { print }
    END {
      if (!replaced) {
        print k "=" v
      }
    }
  ' "${ENV_FILE}" >"${tmp}"

  mv "${tmp}" "${ENV_FILE}"
}

sync_credentials_to_vault() {
  local vault_helper="${REPO_ROOT}/vault/scripts/kv-put.sh"
  if [[ ! -x "${vault_helper}" ]]; then
    echo "Vault sync skipped: helper not found at ${vault_helper}"
    return 0
  fi

  load_env

  if ! "${vault_helper}" "services/gitlab" \
    "mode" "docker" \
    "external_url" "${GITLAB_EXTERNAL_URL:-http://localhost:8929}" \
    "admin_user" "${GITLAB_ADMIN_USER:-admin}" \
    "admin_password" "${GITLAB_ADMIN_PASSWORD:-password}" \
    "regular_user" "${GITLAB_USER:-user}" \
    "regular_password" "${GITLAB_USER_PASSWORD:-password}" \
    "root_username" "root" \
    "root_password" "${GITLAB_ROOT_PASSWORD:-}" \
    "runner_1_token" "${RUNNER_1_TOKEN:-}" \
    "runner_2_token" "${RUNNER_2_TOKEN:-}" \
    "runner_registration_token" "${RUNNER_REGISTRATION_TOKEN:-}"; then
    echo "Warning: failed to sync GitLab credentials to Vault."
  fi
}

wait_for_gitlab_http() {
  local base_url="$1"
  local max_attempts="${2:-180}"
  local delay_seconds="${3:-5}"
  local curl_max_time="${4:-8}"
  local attempt="0"
  local signin_url="${base_url%/}/users/sign_in"
  local http_code

  echo "Waiting for GitLab to become ready at ${signin_url} (up to $((max_attempts * delay_seconds))s)"
  until [[ "${attempt}" -ge "${max_attempts}" ]]; do
    attempt=$((attempt + 1))

    http_code="$(
      curl -sS --output /dev/null --write-out '%{http_code}' \
        --connect-timeout 2 \
        --max-time "${curl_max_time}" \
        "${signin_url}" || true
    )"

    if [[ "${http_code}" == "200" || "${http_code}" == "302" ]]; then
      echo "GitLab HTTP endpoint is ready (${http_code})"
      return 0
    fi

    if [[ "${attempt}" -eq 1 || $((attempt % 6)) -eq 0 ]]; then
      echo "  Still waiting... attempt ${attempt}/${max_attempts} (last HTTP code: ${http_code:-none})"
    fi

    sleep "${delay_seconds}"
  done

  echo "GitLab did not become ready in time at ${signin_url}"
  exit 1
}

create_bootstrap_pat() {
  local max_attempts="${1:-60}"
  local delay_seconds="${2:-5}"
  local attempt="0"
  local token=""
  local script='require "securerandom"; u = User.find_by_username("root") || User.admins.order(:id).first; if u.nil? then warn("admin user not found yet"); exit 3; end; t = SecureRandom.hex(20); p = PersonalAccessToken.new(user: u, name: "bootstrap-runner-#{Time.now.to_i}", scopes: [:api], token: t, expires_at: 1.day.from_now); p.save!; puts t'

  until [[ "${attempt}" -ge "${max_attempts}" ]]; do
    attempt=$((attempt + 1))
    token="$(
      compose exec -T gitlab gitlab-rails runner "${script}" 2>/dev/null | tail -n 1 | tr -d '\r' || true
    )"

    if [[ "${token}" =~ ^[a-f0-9]{40}$ ]]; then
      printf '%s' "${token}"
      return 0
    fi

    if [[ "${attempt}" -eq 1 || $((attempt % 6)) -eq 0 ]]; then
      echo "  Waiting for GitLab admin user before creating PAT... attempt ${attempt}/${max_attempts}" >&2
    fi

    sleep "${delay_seconds}"
  done

  echo "Failed to create bootstrap PAT: admin user not available yet" >&2
  return 1
}

create_runner_token() {
  local pat="$1"
  local runner_name="$2"
  local runner_tags="$3"
  local api_url="$4"
  local max_attempts="${5:-24}"
  local delay_seconds="${6:-5}"
  local attempt="0"
  local response
  local token

  until [[ "${attempt}" -ge "${max_attempts}" ]]; do
    attempt=$((attempt + 1))
    response="$(
      curl -fsS --request POST \
        --connect-timeout 3 \
        --max-time 12 \
        --header "PRIVATE-TOKEN: ${pat}" \
        --data "runner_type=instance_type" \
        --data-urlencode "description=${runner_name}" \
        --data-urlencode "tag_list=${runner_tags}" \
        --data "locked=false" \
        --data "run_untagged=true" \
        "${api_url%/}/api/v4/user/runners" 2>/dev/null || true
    )"

    if [[ -n "${response}" ]]; then
      token="$(printf '%s' "${response}" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
      if [[ -n "${token}" ]]; then
        printf '%s' "${token}"
        return 0
      fi
    fi

    if [[ "${attempt}" -eq 1 || $((attempt % 4)) -eq 0 ]]; then
      echo "  Waiting for runner token API for ${runner_name}... attempt ${attempt}/${max_attempts}" >&2
    fi
    sleep "${delay_seconds}"
  done

  echo "Failed to create runner token for ${runner_name}" >&2
  return 1
}

revoke_pat() {
  local pat="$1"
  local api_url="$2"
  curl -fsS --request DELETE \
    --header "PRIVATE-TOKEN: ${pat}" \
    "${api_url%/}/api/v4/personal_access_tokens/self" >/dev/null 2>&1 || true
}

fetch_registration_token() {
  compose exec -T gitlab gitlab-rails runner 'token = Gitlab::CurrentSettings.current_application_settings.runners_registration_token; puts token.to_s' | tail -n 1
}

ensure_root_password() {
  load_env
  if [[ -z "${GITLAB_ROOT_PASSWORD:-}" || "${GITLAB_ROOT_PASSWORD}" == "${ROOT_PASSWORD_PLACEHOLDER}" ]]; then
    GENERATED_ROOT_PASSWORD="$(random_secret 24)"
    set_env_var "GITLAB_ROOT_PASSWORD" "${GENERATED_ROOT_PASSWORD}"
    echo "Generated GITLAB_ROOT_PASSWORD and saved to ${ENV_FILE}"
  fi
}

ensure_managed_users() {
  load_env

  local max_attempts="${1:-12}"
  local delay_seconds="${2:-5}"
  local attempt="0"
  local output=""
  local admin_username=""
  local regular_username=""
  local runner_script='admin_user = ENV["BOOTSTRAP_ADMIN_USER"].to_s; admin_password = ENV["BOOTSTRAP_ADMIN_PASSWORD"].to_s; regular_user = ENV["BOOTSTRAP_REGULAR_USER"].to_s; regular_password = ENV["BOOTSTRAP_REGULAR_PASSWORD"].to_s; raise "missing BOOTSTRAP_ADMIN_USER" if admin_user.empty?; raise "missing BOOTSTRAP_ADMIN_PASSWORD" if admin_password.empty?; raise "missing BOOTSTRAP_REGULAR_USER" if regular_user.empty?; raise "missing BOOTSTRAP_REGULAR_PASSWORD" if regular_password.empty?; org_id = Organizations::Organization.order(:id).pick(:id); raise "no organization found" if org_id.nil?; ensure_user = lambda do |username, password, email, name, is_admin|; u = User.find_by_username(username); if u.nil?; params = { email: email, username: username, name: name, password: password, password_confirmation: password, admin: is_admin, skip_confirmation: true, organization_id: org_id }; response = Users::CreateService.new(nil, params).execute; unless response.success?; errors = response.payload[:user]&.errors&.full_messages&.join("; "); raise "create #{username} failed: #{response.message} #{errors}".strip; end; u = response.payload[:user]; end; u.password = password; u.password_confirmation = password; u.admin = is_admin; u.organization_id ||= org_id; u.state = "active" if u.respond_to?(:state=) && u.state != "active"; u.skip_confirmation! if u.respond_to?(:skip_confirmation!); u.confirm if u.respond_to?(:confirmed?) && !u.confirmed?; u.save!; end; ensure_user.call(admin_user, admin_password, "admin@example.local", "Administrator", true); ensure_user.call(regular_user, regular_password, "user@example.local", "User", false); puts "bootstrap_admin=#{admin_user}"; puts "bootstrap_user=#{regular_user}"'
  local admin_user="${GITLAB_ADMIN_USER:-admin}"
  local admin_password="${GITLAB_ADMIN_PASSWORD:-password}"
  local regular_user="${GITLAB_USER:-user}"
  local regular_password="${GITLAB_USER_PASSWORD:-password}"

  until [[ "${attempt}" -ge "${max_attempts}" ]]; do
    attempt=$((attempt + 1))
    output="$(
      compose exec -T \
        -e "BOOTSTRAP_ADMIN_USER=${admin_user}" \
        -e "BOOTSTRAP_ADMIN_PASSWORD=${admin_password}" \
        -e "BOOTSTRAP_REGULAR_USER=${regular_user}" \
        -e "BOOTSTRAP_REGULAR_PASSWORD=${regular_password}" \
        gitlab gitlab-rails runner "${runner_script}" 2>/dev/null | tr -d '\r' || true
    )"

    admin_username="$(printf '%s' "${output}" | sed -n 's/^bootstrap_admin=//p' | tail -n 1)"
    regular_username="$(printf '%s' "${output}" | sed -n 's/^bootstrap_user=//p' | tail -n 1)"
    if [[ -n "${admin_username}" && -n "${regular_username}" ]]; then
      LOGIN_ADMIN_USERNAME="${admin_username}"
      LOGIN_REGULAR_USERNAME="${regular_username}"
      return 0
    fi

    if [[ "${attempt}" -eq 1 || $((attempt % 4)) -eq 0 ]]; then
      echo "  Waiting for GitLab managed user bootstrap... attempt ${attempt}/${max_attempts}" >&2
    fi

    sleep "${delay_seconds}"
  done

  echo "Could not create/sync GitLab managed users"
  exit 1
}

ensure_runner_credentials() {
  load_env

  if [[ -n "${RUNNER_1_TOKEN:-}" && -n "${RUNNER_2_TOKEN:-}" ]]; then
    return 0
  fi

  if [[ -n "${RUNNER_REGISTRATION_TOKEN:-}" ]]; then
    return 0
  fi

  local api_url="${GITLAB_EXTERNAL_URL:-http://localhost:8929}"
  local pat
  local runner1_token
  local runner2_token
  local registration_token

  echo "Generating runner credentials automatically"
  pat="$(create_bootstrap_pat 12 5 || true)"

  if [[ -n "${pat}" ]] \
    && runner1_token="$(create_runner_token "${pat}" "gitlab-worker-1" "worker-1,docker" "${api_url}")" \
    && runner2_token="$(create_runner_token "${pat}" "gitlab-worker-2" "worker-2,docker" "${api_url}")"; then
    set_env_var "RUNNER_1_TOKEN" "${runner1_token}"
    set_env_var "RUNNER_2_TOKEN" "${runner2_token}"
    GENERATED_RUNNER_1_TOKEN="${runner1_token}"
    GENERATED_RUNNER_2_TOKEN="${runner2_token}"
    echo "Generated RUNNER_1_TOKEN and RUNNER_2_TOKEN and saved to ${ENV_FILE}"
  else
    if [[ -z "${pat}" ]]; then
      echo "  Could not create admin PAT yet; trying RUNNER_REGISTRATION_TOKEN fallback" >&2
    fi

    registration_token="$(fetch_registration_token || true)"
    if [[ -n "${registration_token}" ]]; then
      set_env_var "RUNNER_REGISTRATION_TOKEN" "${registration_token}"
      GENERATED_REGISTRATION_TOKEN="${registration_token}"
      echo "Fell back to generated RUNNER_REGISTRATION_TOKEN and saved to ${ENV_FILE}"
    else
      if [[ -n "${pat}" ]]; then
        revoke_pat "${pat}" "${api_url}"
      fi
      echo "Could not generate runner credentials automatically"
      exit 1
    fi
  fi

  if [[ -n "${pat}" ]]; then
    revoke_pat "${pat}" "${api_url}"
  fi
}

print_credentials() {
  load_env

  echo ""
  echo "GitLab login"
  echo "  URL: ${GITLAB_EXTERNAL_URL:-http://localhost:8929}"
  echo "  Admin username: ${LOGIN_ADMIN_USERNAME}"
  echo "  Admin password: ${GITLAB_ADMIN_PASSWORD:-password}"
  echo "  User username: ${LOGIN_REGULAR_USERNAME}"
  echo "  User password: ${GITLAB_USER_PASSWORD:-password}"

  if [[ -n "${GENERATED_RUNNER_1_TOKEN}" || -n "${GENERATED_RUNNER_2_TOKEN}" ]]; then
    echo ""
    echo "Generated runner auth tokens"
    [[ -n "${GENERATED_RUNNER_1_TOKEN}" ]] && echo "  RUNNER_1_TOKEN=${GENERATED_RUNNER_1_TOKEN}"
    [[ -n "${GENERATED_RUNNER_2_TOKEN}" ]] && echo "  RUNNER_2_TOKEN=${GENERATED_RUNNER_2_TOKEN}"
  fi

  if [[ -n "${GENERATED_REGISTRATION_TOKEN}" ]]; then
    echo ""
    echo "Generated runner registration token"
    echo "  RUNNER_REGISTRATION_TOKEN=${GENERATED_REGISTRATION_TOKEN}"
  fi
}

ensure_root_password

compose up -d gitlab

load_env
wait_for_gitlab_http "${GITLAB_EXTERNAL_URL:-http://localhost:8929}"
ensure_managed_users

ensure_runner_credentials

sync_credentials_to_vault

compose up -d gitlab gitlab-runner-1 gitlab-runner-2
compose ps

print_credentials
