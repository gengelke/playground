#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

to_abs_path() {
  local path="$1"
  case "$path" in
    /*) printf '%s' "$path" ;;
    *) printf '%s/%s' "$ROOT_DIR" "${path#./}" ;;
  esac
}

STATE_DIR="$(to_abs_path "${STATE_DIR:-${ROOT_DIR}/.state}")"
CACHE_DIR="$(to_abs_path "${CACHE_DIR:-${STATE_DIR}/cache}")"
BARE_STATE_DIR="$(to_abs_path "${BARE_STATE_DIR:-${STATE_DIR}/bare}")"

PIPELINE_REPO_URL="${PIPELINE_REPO_URL:-}"
PROD_PIPELINE_REPO_URL="${PROD_PIPELINE_REPO_URL:-}"
DEV_PIPELINE_REPO_URL="${DEV_PIPELINE_REPO_URL:-}"
PIPELINE_GIT_CREDENTIALS_ID="${PIPELINE_GIT_CREDENTIALS_ID:-}"
PIPELINE_GIT_USERNAME="${PIPELINE_GIT_USERNAME:-}"
PIPELINE_GIT_PASSWORD="${PIPELINE_GIT_PASSWORD:-}"
PROD_PIPELINE_GIT_CREDENTIALS_ID="${PROD_PIPELINE_GIT_CREDENTIALS_ID:-}"
PROD_PIPELINE_GIT_USERNAME="${PROD_PIPELINE_GIT_USERNAME:-}"
PROD_PIPELINE_GIT_PASSWORD="${PROD_PIPELINE_GIT_PASSWORD:-}"
DEV_PIPELINE_GIT_CREDENTIALS_ID="${DEV_PIPELINE_GIT_CREDENTIALS_ID:-}"
DEV_PIPELINE_GIT_USERNAME="${DEV_PIPELINE_GIT_USERNAME:-}"
DEV_PIPELINE_GIT_PASSWORD="${DEV_PIPELINE_GIT_PASSWORD:-}"
GENERATE_LIBRARY_PIPELINE_REPO_URL="${GENERATE_LIBRARY_PIPELINE_REPO_URL:-}"
PROD_GENERATE_LIBRARY_PIPELINE_REPO_URL="${PROD_GENERATE_LIBRARY_PIPELINE_REPO_URL:-}"
DEV_GENERATE_LIBRARY_PIPELINE_REPO_URL="${DEV_GENERATE_LIBRARY_PIPELINE_REPO_URL:-}"
GENERATE_LIBRARY_PIPELINE_BRANCH="${GENERATE_LIBRARY_PIPELINE_BRANCH:-}"
PROD_GENERATE_LIBRARY_PIPELINE_BRANCH="${PROD_GENERATE_LIBRARY_PIPELINE_BRANCH:-}"
DEV_GENERATE_LIBRARY_PIPELINE_BRANCH="${DEV_GENERATE_LIBRARY_PIPELINE_BRANCH:-}"
GENERATE_LIBRARY_SOURCE_REPO_URL="${GENERATE_LIBRARY_SOURCE_REPO_URL:-}"
PROD_GENERATE_LIBRARY_SOURCE_REPO_URL="${PROD_GENERATE_LIBRARY_SOURCE_REPO_URL:-}"
DEV_GENERATE_LIBRARY_SOURCE_REPO_URL="${DEV_GENERATE_LIBRARY_SOURCE_REPO_URL:-}"
GENERATE_LIBRARY_SOURCE_BRANCH="${GENERATE_LIBRARY_SOURCE_BRANCH:-}"
PROD_GENERATE_LIBRARY_SOURCE_BRANCH="${PROD_GENERATE_LIBRARY_SOURCE_BRANCH:-}"
DEV_GENERATE_LIBRARY_SOURCE_BRANCH="${DEV_GENERATE_LIBRARY_SOURCE_BRANCH:-}"
LIBRARY_EXAMPLE_CLIENT_PIPELINE_REPO_URL="${LIBRARY_EXAMPLE_CLIENT_PIPELINE_REPO_URL:-}"
PROD_LIBRARY_EXAMPLE_CLIENT_PIPELINE_REPO_URL="${PROD_LIBRARY_EXAMPLE_CLIENT_PIPELINE_REPO_URL:-}"
DEV_LIBRARY_EXAMPLE_CLIENT_PIPELINE_REPO_URL="${DEV_LIBRARY_EXAMPLE_CLIENT_PIPELINE_REPO_URL:-}"
LIBRARY_EXAMPLE_CLIENT_PIPELINE_BRANCH="${LIBRARY_EXAMPLE_CLIENT_PIPELINE_BRANCH:-}"
PROD_LIBRARY_EXAMPLE_CLIENT_PIPELINE_BRANCH="${PROD_LIBRARY_EXAMPLE_CLIENT_PIPELINE_BRANCH:-}"
DEV_LIBRARY_EXAMPLE_CLIENT_PIPELINE_BRANCH="${DEV_LIBRARY_EXAMPLE_CLIENT_PIPELINE_BRANCH:-}"
LIBRARY_EXAMPLE_CLIENT_SOURCE_REPO_URL="${LIBRARY_EXAMPLE_CLIENT_SOURCE_REPO_URL:-}"
PROD_LIBRARY_EXAMPLE_CLIENT_SOURCE_REPO_URL="${PROD_LIBRARY_EXAMPLE_CLIENT_SOURCE_REPO_URL:-}"
DEV_LIBRARY_EXAMPLE_CLIENT_SOURCE_REPO_URL="${DEV_LIBRARY_EXAMPLE_CLIENT_SOURCE_REPO_URL:-}"
LIBRARY_EXAMPLE_CLIENT_SOURCE_BRANCH="${LIBRARY_EXAMPLE_CLIENT_SOURCE_BRANCH:-}"
PROD_LIBRARY_EXAMPLE_CLIENT_SOURCE_BRANCH="${PROD_LIBRARY_EXAMPLE_CLIENT_SOURCE_BRANCH:-}"
DEV_LIBRARY_EXAMPLE_CLIENT_SOURCE_BRANCH="${DEV_LIBRARY_EXAMPLE_CLIENT_SOURCE_BRANCH:-}"
PROD_BRANCH="${PROD_BRANCH:-main}"
DEV_BRANCH="${DEV_BRANCH:-dev}"
PIPELINE_SCRIPT_PATH="${PIPELINE_SCRIPT_PATH:-Jenkinsfile}"
PIPELINE_JOB_NAME="${PIPELINE_JOB_NAME:-example-pipeline}"
PIPELINE_AUTH_TOKEN="${PIPELINE_AUTH_TOKEN:-example-pipeline-auth-token}"
PIPELINE_AUTO_TRIGGER="${PIPELINE_AUTO_TRIGGER:-true}"
GENERATE_LIBRARY_PIPELINE_AUTO_TRIGGER="${GENERATE_LIBRARY_PIPELINE_AUTO_TRIGGER:-false}"
LIBRARY_EXAMPLE_CLIENT_PIPELINE_JOB_NAME="${LIBRARY_EXAMPLE_CLIENT_PIPELINE_JOB_NAME:-library-example-client}"
LIBRARY_EXAMPLE_CLIENT_PIPELINE_AUTH_TOKEN="${LIBRARY_EXAMPLE_CLIENT_PIPELINE_AUTH_TOKEN:-}"
LIBRARY_EXAMPLE_CLIENT_PIPELINE_AUTO_TRIGGER="${LIBRARY_EXAMPLE_CLIENT_PIPELINE_AUTO_TRIGGER:-false}"

AGENT_COUNT="${AGENT_COUNT:-2}"
AGENT_EXECUTORS="${AGENT_EXECUTORS:-1}"
PROD_HTTP_PORT="${PROD_HTTP_PORT:-8081}"
DEV_HTTP_PORT="${DEV_HTTP_PORT:-8082}"
PROD_JENKINS_ROOT_URL="${PROD_JENKINS_ROOT_URL:-}"
DEV_JENKINS_ROOT_URL="${DEV_JENKINS_ROOT_URL:-}"
JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER:-admin}"
JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD:-password}"
JENKINS_REGULAR_USER="${JENKINS_REGULAR_USER:-user}"
JENKINS_REGULAR_PASSWORD="${JENKINS_REGULAR_PASSWORD:-password}"
JENKINS_CSP="${JENKINS_CSP:-}"
JENKINS_TIMEZONE="${JENKINS_TIMEZONE:-Europe/Berlin}"
VAULT_ADDR="${VAULT_ADDR:-}"
VAULT_TOKEN="${VAULT_TOKEN:-}"
NEXUS_PYPI_REPO="${NEXUS_PYPI_REPO:-pypi-public}"

CREDENTIALS_DIR="$(to_abs_path "${CREDENTIALS_DIR:-${STATE_DIR}/credentials}")"
ADMIN_PASSWORD_FILE="$(to_abs_path "${ADMIN_PASSWORD_FILE:-${CREDENTIALS_DIR}/admin-password}")"
ADMIN_PASSWORD_GENERATED=0

JENKINS_WAR_URL="${JENKINS_WAR_URL:-https://get.jenkins.io/war-stable/latest/jenkins.war}"
JENKINS_WAR_PATH="${JENKINS_WAR_PATH:-${CACHE_DIR}/jenkins.war}"
INIT_GROOVY_DIR="${INIT_GROOVY_DIR:-${ROOT_DIR}/controller/init.groovy.d}"
GITEA_GENERATED_ENV_FILE="${GITEA_GENERATED_ENV_FILE:-${ROOT_DIR}/../gitea/runtime/shared/generated.env}"
VAULT_CREDS_FILE="${VAULT_CREDS_FILE:-${ROOT_DIR}/../vault/.vault/credentials.env}"

JAVA_BIN="${JAVA_BIN:-java}"
CURL_BIN="${CURL_BIN:-curl}"

generate_admin_password() {
  od -An -N18 -tx1 /dev/urandom | tr -d ' \n'
}

sync_jenkins_credentials_to_vault() {
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
    "prod_url" "$(resolve_instance_root_url "prod")" \
    "dev_url" "$(resolve_instance_root_url "dev")"; then
    echo "Warning: failed to sync Jenkins credentials to Vault."
  fi
}

ensure_admin_credentials() {
  mkdir -p "$CREDENTIALS_DIR"
  ADMIN_PASSWORD_GENERATED=0

  if [[ -z "${JENKINS_ADMIN_PASSWORD}" ]]; then
    if [[ -s "$ADMIN_PASSWORD_FILE" ]]; then
      JENKINS_ADMIN_PASSWORD="$(cat "$ADMIN_PASSWORD_FILE")"
    else
      JENKINS_ADMIN_PASSWORD="$(generate_admin_password)"
      printf '%s' "$JENKINS_ADMIN_PASSWORD" > "$ADMIN_PASSWORD_FILE"
      ADMIN_PASSWORD_GENERATED=1
    fi
  fi

  export JENKINS_ADMIN_USER JENKINS_ADMIN_PASSWORD JENKINS_REGULAR_USER JENKINS_REGULAR_PASSWORD ADMIN_PASSWORD_GENERATED
  sync_jenkins_credentials_to_vault
}

print_admin_credentials() {
  echo "Jenkins admin user: ${JENKINS_ADMIN_USER}"
  if [[ "${ADMIN_PASSWORD_GENERATED:-0}" == "1" ]]; then
    echo "Jenkins admin password (generated): ${JENKINS_ADMIN_PASSWORD}"
    echo "Saved generated password to ${ADMIN_PASSWORD_FILE}"
    return
  fi

  if [[ -n "${JENKINS_ADMIN_PASSWORD:-}" ]]; then
    if [[ -s "$ADMIN_PASSWORD_FILE" ]] && [[ "${JENKINS_ADMIN_PASSWORD}" == "$(cat "$ADMIN_PASSWORD_FILE")" ]]; then
      echo "Jenkins admin password (from ${ADMIN_PASSWORD_FILE}): ${JENKINS_ADMIN_PASSWORD}"
    else
      echo "Jenkins admin password (from environment): ${JENKINS_ADMIN_PASSWORD}"
    fi
  else
    echo "Jenkins admin password is not set"
  fi
}

resolve_instance_pipeline_repo_url() {
  local mode="$1"
  local instance="$2"

  case "$instance" in
    prod)
      if [[ -n "${PROD_PIPELINE_REPO_URL}" ]]; then
        printf '%s' "${PROD_PIPELINE_REPO_URL}"
        return
      fi
      case "$mode" in
        docker) printf 'http://host.docker.internal:3000/myuser/jenkins-example' ;;
        bare) printf 'http://127.0.0.1:3000/myuser/jenkins-example' ;;
        *)
          echo "unknown mode: ${mode}" >&2
          return 1
          ;;
      esac
      return
      ;;
    dev)
      if [[ -n "${DEV_PIPELINE_REPO_URL}" ]]; then
        printf '%s' "${DEV_PIPELINE_REPO_URL}"
        return
      fi
      case "$mode" in
        docker) printf 'http://host.docker.internal:3000/myuser/jenkins-example' ;;
        bare) printf 'http://127.0.0.1:3000/myuser/jenkins-example' ;;
        *)
          echo "unknown mode: ${mode}" >&2
          return 1
          ;;
      esac
      return
      ;;
    *)
      echo "unknown instance: ${instance}" >&2
      return 1
      ;;
  esac
}

resolve_instance_generate_library_pipeline_repo_url() {
  local mode="$1"
  local instance="$2"

  if [[ -n "${GENERATE_LIBRARY_PIPELINE_REPO_URL}" ]]; then
    printf '%s' "${GENERATE_LIBRARY_PIPELINE_REPO_URL}"
    return
  fi

  case "$instance" in
    prod)
      if [[ -n "${PROD_GENERATE_LIBRARY_PIPELINE_REPO_URL}" ]]; then
        printf '%s' "${PROD_GENERATE_LIBRARY_PIPELINE_REPO_URL}"
        return
      fi
      case "$mode" in
        docker) printf 'http://host.docker.internal:3000/myuser/generate-library' ;;
        bare) printf 'http://127.0.0.1:3000/myuser/generate-library' ;;
        *)
          echo "unknown mode: ${mode}" >&2
          return 1
          ;;
      esac
      return
      ;;
    dev)
      if [[ -n "${DEV_GENERATE_LIBRARY_PIPELINE_REPO_URL}" ]]; then
        printf '%s' "${DEV_GENERATE_LIBRARY_PIPELINE_REPO_URL}"
        return
      fi
      case "$mode" in
        docker) printf 'http://host.docker.internal:3000/myuser/generate-library' ;;
        bare) printf 'http://127.0.0.1:3000/myuser/generate-library' ;;
        *)
          echo "unknown mode: ${mode}" >&2
          return 1
          ;;
      esac
      return
      ;;
    *)
      echo "unknown instance: ${instance}" >&2
      return 1
      ;;
  esac
}

resolve_instance_generate_library_pipeline_branch() {
  local instance="$1"

  if [[ -n "${GENERATE_LIBRARY_PIPELINE_BRANCH}" ]]; then
    printf '%s' "${GENERATE_LIBRARY_PIPELINE_BRANCH}"
    return
  fi

  case "$instance" in
    prod) printf '%s' "${PROD_GENERATE_LIBRARY_PIPELINE_BRANCH:-${PROD_BRANCH}}" ;;
    dev) printf '%s' "${DEV_GENERATE_LIBRARY_PIPELINE_BRANCH:-${DEV_BRANCH}}" ;;
    *)
      echo "unknown instance: ${instance}" >&2
      return 1
      ;;
  esac
}

resolve_instance_generate_library_source_repo_url() {
  local instance="$1"

  if [[ -n "${GENERATE_LIBRARY_SOURCE_REPO_URL}" ]]; then
    printf '%s' "${GENERATE_LIBRARY_SOURCE_REPO_URL}"
    return
  fi

  case "$instance" in
    prod)
      if [[ -n "${PROD_GENERATE_LIBRARY_SOURCE_REPO_URL}" ]]; then
        printf '%s' "${PROD_GENERATE_LIBRARY_SOURCE_REPO_URL}"
        return
      fi
      ;;
    dev)
      if [[ -n "${DEV_GENERATE_LIBRARY_SOURCE_REPO_URL}" ]]; then
        printf '%s' "${DEV_GENERATE_LIBRARY_SOURCE_REPO_URL}"
        return
      fi
      ;;
    *)
      echo "unknown instance: ${instance}" >&2
      return 1
      ;;
  esac

  printf '%s' 'https://github.com/gengelke/playground.git'
}

resolve_instance_generate_library_source_branch() {
  local instance="$1"

  if [[ -n "${GENERATE_LIBRARY_SOURCE_BRANCH}" ]]; then
    printf '%s' "${GENERATE_LIBRARY_SOURCE_BRANCH}"
    return
  fi

  case "$instance" in
    prod)
      if [[ -n "${PROD_GENERATE_LIBRARY_SOURCE_BRANCH}" ]]; then
        printf '%s' "${PROD_GENERATE_LIBRARY_SOURCE_BRANCH}"
        return
      fi
      ;;
    dev)
      if [[ -n "${DEV_GENERATE_LIBRARY_SOURCE_BRANCH}" ]]; then
        printf '%s' "${DEV_GENERATE_LIBRARY_SOURCE_BRANCH}"
        return
      fi
      ;;
    *)
      echo "unknown instance: ${instance}" >&2
      return 1
      ;;
  esac

  resolve_instance_generate_library_pipeline_branch "$instance"
}

resolve_instance_library_example_client_pipeline_repo_url() {
  local mode="$1"
  local instance="$2"

  if [[ -n "${LIBRARY_EXAMPLE_CLIENT_PIPELINE_REPO_URL}" ]]; then
    printf '%s' "${LIBRARY_EXAMPLE_CLIENT_PIPELINE_REPO_URL}"
    return
  fi

  case "$instance" in
    prod)
      if [[ -n "${PROD_LIBRARY_EXAMPLE_CLIENT_PIPELINE_REPO_URL}" ]]; then
        printf '%s' "${PROD_LIBRARY_EXAMPLE_CLIENT_PIPELINE_REPO_URL}"
        return
      fi
      case "$mode" in
        docker) printf 'http://host.docker.internal:3000/myuser/library-example-client' ;;
        bare) printf 'http://127.0.0.1:3000/myuser/library-example-client' ;;
        *)
          echo "unknown mode: ${mode}" >&2
          return 1
          ;;
      esac
      return
      ;;
    dev)
      if [[ -n "${DEV_LIBRARY_EXAMPLE_CLIENT_PIPELINE_REPO_URL}" ]]; then
        printf '%s' "${DEV_LIBRARY_EXAMPLE_CLIENT_PIPELINE_REPO_URL}"
        return
      fi
      case "$mode" in
        docker) printf 'http://host.docker.internal:3000/myuser/library-example-client' ;;
        bare) printf 'http://127.0.0.1:3000/myuser/library-example-client' ;;
        *)
          echo "unknown mode: ${mode}" >&2
          return 1
          ;;
      esac
      return
      ;;
    *)
      echo "unknown instance: ${instance}" >&2
      return 1
      ;;
  esac
}

resolve_instance_library_example_client_pipeline_branch() {
  local instance="$1"

  if [[ -n "${LIBRARY_EXAMPLE_CLIENT_PIPELINE_BRANCH}" ]]; then
    printf '%s' "${LIBRARY_EXAMPLE_CLIENT_PIPELINE_BRANCH}"
    return
  fi

  case "$instance" in
    prod) printf '%s' "${PROD_LIBRARY_EXAMPLE_CLIENT_PIPELINE_BRANCH:-${PROD_BRANCH}}" ;;
    dev) printf '%s' "${DEV_LIBRARY_EXAMPLE_CLIENT_PIPELINE_BRANCH:-${DEV_BRANCH}}" ;;
    *)
      echo "unknown instance: ${instance}" >&2
      return 1
      ;;
  esac
}

resolve_instance_library_example_client_source_repo_url() {
  local instance="$1"

  if [[ -n "${LIBRARY_EXAMPLE_CLIENT_SOURCE_REPO_URL}" ]]; then
    printf '%s' "${LIBRARY_EXAMPLE_CLIENT_SOURCE_REPO_URL}"
    return
  fi

  case "$instance" in
    prod)
      if [[ -n "${PROD_LIBRARY_EXAMPLE_CLIENT_SOURCE_REPO_URL}" ]]; then
        printf '%s' "${PROD_LIBRARY_EXAMPLE_CLIENT_SOURCE_REPO_URL}"
        return
      fi
      ;;
    dev)
      if [[ -n "${DEV_LIBRARY_EXAMPLE_CLIENT_SOURCE_REPO_URL}" ]]; then
        printf '%s' "${DEV_LIBRARY_EXAMPLE_CLIENT_SOURCE_REPO_URL}"
        return
      fi
      ;;
    *)
      echo "unknown instance: ${instance}" >&2
      return 1
      ;;
  esac

  printf '%s' 'https://github.com/gengelke/playground.git'
}

resolve_instance_library_example_client_source_branch() {
  local instance="$1"

  if [[ -n "${LIBRARY_EXAMPLE_CLIENT_SOURCE_BRANCH}" ]]; then
    printf '%s' "${LIBRARY_EXAMPLE_CLIENT_SOURCE_BRANCH}"
    return
  fi

  case "$instance" in
    prod)
      if [[ -n "${PROD_LIBRARY_EXAMPLE_CLIENT_SOURCE_BRANCH}" ]]; then
        printf '%s' "${PROD_LIBRARY_EXAMPLE_CLIENT_SOURCE_BRANCH}"
        return
      fi
      ;;
    dev)
      if [[ -n "${DEV_LIBRARY_EXAMPLE_CLIENT_SOURCE_BRANCH}" ]]; then
        printf '%s' "${DEV_LIBRARY_EXAMPLE_CLIENT_SOURCE_BRANCH}"
        return
      fi
      ;;
    *)
      echo "unknown instance: ${instance}" >&2
      return 1
      ;;
  esac

  resolve_instance_library_example_client_pipeline_branch "$instance"
}

read_env_file_value() {
  local file_path="$1"
  local key="$2"

  [[ -f "$file_path" ]] || return 1
  grep -E "^${key}=" "$file_path" | tail -n1 | cut -d= -f2-
}

normalize_localhost_for_mode() {
  local mode="$1"
  local value="$2"

  if [[ "$mode" != "docker" ]]; then
    printf '%s' "$value"
    return
  fi

  printf '%s' "$value" | sed \
    -e 's#http://localhost#http://host.docker.internal#g' \
    -e 's#http://127.0.0.1#http://host.docker.internal#g' \
    -e 's#https://localhost#https://host.docker.internal#g' \
    -e 's#https://127.0.0.1#https://host.docker.internal#g'
}

resolve_vault_addr() {
  local mode="$1"
  local value="${VAULT_ADDR:-}"

  if [[ -z "$value" ]]; then
    value="$(read_env_file_value "$VAULT_CREDS_FILE" "VAULT_ADDR" 2>/dev/null || true)"
  fi
  if [[ -z "$value" ]]; then
    value="http://127.0.0.1:8200"
  fi

  normalize_localhost_for_mode "$mode" "$value"
}

resolve_vault_token() {
  local value="${VAULT_TOKEN:-${VAULT_ROOT_TOKEN:-}}"

  if [[ -z "$value" ]]; then
    value="$(read_env_file_value "$VAULT_CREDS_FILE" "VAULT_TOKEN" 2>/dev/null || true)"
  fi
  if [[ -z "$value" ]]; then
    value="$(read_env_file_value "$VAULT_CREDS_FILE" "VAULT_ROOT_TOKEN" 2>/dev/null || true)"
  fi

  printf '%s' "$value"
}

resolve_instance_pipeline_git_username() {
  local mode="$1"
  local instance="$2"
  local _unused_mode="$mode"
  local value=""

  case "$instance" in
    prod) value="${PROD_PIPELINE_GIT_USERNAME:-${PIPELINE_GIT_USERNAME:-}}" ;;
    dev) value="${DEV_PIPELINE_GIT_USERNAME:-${PIPELINE_GIT_USERNAME:-}}" ;;
    *)
      echo "unknown instance: ${instance}" >&2
      return 1
      ;;
  esac

  if [[ -z "$value" && ( "$instance" == "dev" || "$instance" == "prod" ) ]]; then
    value="$(read_env_file_value "$GITEA_GENERATED_ENV_FILE" "GITEA_USER" 2>/dev/null || true)"
  fi

  printf '%s' "$value"
}

resolve_instance_pipeline_git_password() {
  local mode="$1"
  local instance="$2"
  local _unused_mode="$mode"
  local value=""

  case "$instance" in
    prod) value="${PROD_PIPELINE_GIT_PASSWORD:-${PIPELINE_GIT_PASSWORD:-}}" ;;
    dev) value="${DEV_PIPELINE_GIT_PASSWORD:-${PIPELINE_GIT_PASSWORD:-}}" ;;
    *)
      echo "unknown instance: ${instance}" >&2
      return 1
      ;;
  esac

  if [[ -z "$value" && ( "$instance" == "dev" || "$instance" == "prod" ) ]]; then
    value="$(read_env_file_value "$GITEA_GENERATED_ENV_FILE" "GITEA_USER_PASSWORD" 2>/dev/null || true)"
  fi

  printf '%s' "$value"
}

resolve_instance_pipeline_git_credentials_id() {
  local mode="$1"
  local instance="$2"
  local value username password

  case "$instance" in
    prod) value="${PROD_PIPELINE_GIT_CREDENTIALS_ID:-${PIPELINE_GIT_CREDENTIALS_ID:-}}" ;;
    dev) value="${DEV_PIPELINE_GIT_CREDENTIALS_ID:-${PIPELINE_GIT_CREDENTIALS_ID:-}}" ;;
    *)
      echo "unknown instance: ${instance}" >&2
      return 1
      ;;
  esac

  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return
  fi

  username="$(resolve_instance_pipeline_git_username "$mode" "$instance")"
  password="$(resolve_instance_pipeline_git_password "$mode" "$instance")"
  if [[ -n "$username" && -n "$password" ]]; then
    printf 'pipeline-git-%s' "$instance"
    return
  fi

  printf ''
}

print_pipeline_configuration() {
  local prod_repo_url="$1"
  local dev_repo_url="$2"
  local prod_credentials_id="$3"
  local dev_credentials_id="$4"
  echo "Pipeline source repository (prod): ${prod_repo_url}"
  echo "Pipeline source repository (dev):  ${dev_repo_url}"
  echo "Pipeline git credentials id (prod): ${prod_credentials_id:-<none>}"
  echo "Pipeline git credentials id (dev):  ${dev_credentials_id:-<none>}"
  echo "Pipeline branches: prod=${PROD_BRANCH}, dev=${DEV_BRANCH}"
  echo "Pipeline job name: ${PIPELINE_JOB_NAME}"
  echo "Pipeline script path: ${PIPELINE_SCRIPT_PATH}"
}

print_instance_urls() {
  echo "Jenkins instance URLs:"
  echo "  jenkins-prod: $(resolve_instance_root_url "prod")"
  echo "  jenkins-dev:  $(resolve_instance_root_url "dev")"
}

instance_name() {
  local instance="$1"
  printf 'jenkins-%s' "$instance"
}

instance_http_port() {
  local instance="$1"
  case "$instance" in
    prod) printf '%s' "$PROD_HTTP_PORT" ;;
    dev) printf '%s' "$DEV_HTTP_PORT" ;;
    *)
      echo "unknown instance: ${instance}" >&2
      return 1
      ;;
  esac
}

instance_branch() {
  local instance="$1"
  case "$instance" in
    prod) printf '%s' "$PROD_BRANCH" ;;
    dev) printf '%s' "$DEV_BRANCH" ;;
    *)
      echo "unknown instance: ${instance}" >&2
      return 1
      ;;
  esac
}

instance_base_url() {
  local instance="$1"
  printf 'http://127.0.0.1:%s/' "$(instance_http_port "$instance")"
}

resolve_instance_root_url() {
  local instance="$1"
  local value=""

  case "$instance" in
    prod) value="${PROD_JENKINS_ROOT_URL:-}" ;;
    dev) value="${DEV_JENKINS_ROOT_URL:-}" ;;
    *)
      echo "unknown instance: ${instance}" >&2
      return 1
      ;;
  esac

  if [[ -z "$value" ]]; then
    value="$(instance_base_url "$instance")"
  fi

  if [[ "$value" != */ ]]; then
    value="${value}/"
  fi

  printf '%s' "$value"
}

instance_dir() {
  local instance="$1"
  printf '%s/%s' "$BARE_STATE_DIR" "$instance"
}

instance_home() {
  local instance="$1"
  printf '%s/home' "$(instance_dir "$instance")"
}

instance_logs_dir() {
  local instance="$1"
  printf '%s/logs' "$(instance_dir "$instance")"
}

instance_controller_pid_file() {
  local instance="$1"
  printf '%s/controller.pid' "$(instance_dir "$instance")"
}

agent_name() {
  local instance="$1"
  local index="$2"
  printf '%s-agent-%s' "$(instance_name "$instance")" "$index"
}

agent_dir() {
  local instance="$1"
  local index="$2"
  printf '%s/agents/%s' "$(instance_dir "$instance")" "$(agent_name "$instance" "$index")"
}

agent_pid_file() {
  local instance="$1"
  local index="$2"
  printf '%s/agent.pid' "$(agent_dir "$instance" "$index")"
}

is_pid_running() {
  local pid_file="$1"
  [[ -f "$pid_file" ]] || return 1

  local pid
  pid="$(cat "$pid_file")"
  [[ -n "$pid" ]] || return 1

  kill -0 "$pid" 2>/dev/null
}
