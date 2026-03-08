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
PROD_BRANCH="${PROD_BRANCH:-main}"
DEV_BRANCH="${DEV_BRANCH:-dev}"
PIPELINE_SCRIPT_PATH="${PIPELINE_SCRIPT_PATH:-Jenkinsfile}"
PIPELINE_JOB_NAME="${PIPELINE_JOB_NAME:-example-pipeline}"
PIPELINE_AUTH_TOKEN="${PIPELINE_AUTH_TOKEN:-example-pipeline-auth-token}"

AGENT_COUNT="${AGENT_COUNT:-2}"
AGENT_EXECUTORS="${AGENT_EXECUTORS:-1}"
PROD_HTTP_PORT="${PROD_HTTP_PORT:-8081}"
DEV_HTTP_PORT="${DEV_HTTP_PORT:-8082}"
JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER:-admin}"
JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD:-password}"
JENKINS_REGULAR_USER="${JENKINS_REGULAR_USER:-user}"
JENKINS_REGULAR_PASSWORD="${JENKINS_REGULAR_PASSWORD:-password}"

CREDENTIALS_DIR="$(to_abs_path "${CREDENTIALS_DIR:-${STATE_DIR}/credentials}")"
ADMIN_PASSWORD_FILE="$(to_abs_path "${ADMIN_PASSWORD_FILE:-${CREDENTIALS_DIR}/admin-password}")"
ADMIN_PASSWORD_GENERATED=0
EXAMPLE_PIPELINE_REPO_DIR="$(to_abs_path "${EXAMPLE_PIPELINE_REPO_DIR:-${STATE_DIR}/repo-a}")"

JENKINS_WAR_URL="${JENKINS_WAR_URL:-https://get.jenkins.io/war-stable/latest/jenkins.war}"
JENKINS_WAR_PATH="${JENKINS_WAR_PATH:-${CACHE_DIR}/jenkins.war}"
INIT_GROOVY_DIR="${INIT_GROOVY_DIR:-${ROOT_DIR}/jenkins/controller/init.groovy.d}"

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
    "prod_url" "$(instance_base_url "prod")" \
    "dev_url" "$(instance_base_url "dev")"; then
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

write_example_jenkinsfile() {
  local file_path="${1:-${EXAMPLE_PIPELINE_REPO_DIR}/Jenkinsfile}"
  cat > "${file_path}" <<'EOF'
pipeline {
  agent { label 'linux' }
  stages {
    stage('Hello') {
      steps {
        echo 'hello world'
      }
    }
  }
}
EOF
}

ensure_example_pipeline_repo() {
  mkdir -p "${EXAMPLE_PIPELINE_REPO_DIR}"

  if [[ ! -d "${EXAMPLE_PIPELINE_REPO_DIR}/.git" ]]; then
    git init "${EXAMPLE_PIPELINE_REPO_DIR}" >/dev/null
  fi

  (
    cd "${EXAMPLE_PIPELINE_REPO_DIR}"
    git config user.name "Jenkins Bootstrap"
    git config user.email "jenkins-bootstrap@example.local"

    if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
      git checkout -B main >/dev/null 2>&1
      write_example_jenkinsfile "${PWD}/Jenkinsfile"
      git add Jenkinsfile
      git commit -m "Add example Jenkinsfile" >/dev/null
      git branch -f dev main >/dev/null
      git checkout main >/dev/null 2>&1
      return
    fi

    git checkout -B main >/dev/null 2>&1
    write_example_jenkinsfile "${PWD}/Jenkinsfile"
    if ! git diff --quiet -- Jenkinsfile >/dev/null 2>&1; then
      git add Jenkinsfile
      git commit -m "Update example Jenkinsfile" >/dev/null
    fi
    git branch -f dev main >/dev/null
    git checkout main >/dev/null 2>&1
  )
}

resolve_pipeline_repo_url() {
  local mode="$1"

  if [[ -n "${PIPELINE_REPO_URL}" ]]; then
    printf '%s' "${PIPELINE_REPO_URL}"
    return
  fi

  ensure_example_pipeline_repo

  case "$mode" in
    docker) printf 'file:///opt/pipeline-repo' ;;
    bare) printf 'file://%s' "${EXAMPLE_PIPELINE_REPO_DIR}" ;;
    *)
      echo "unknown mode: ${mode}" >&2
      return 1
      ;;
  esac
}

print_pipeline_configuration() {
  local repo_url="$1"
  echo "Pipeline source repository (Repo A): ${repo_url}"
  echo "Pipeline branches: prod=${PROD_BRANCH}, dev=${DEV_BRANCH}"
  echo "Pipeline job name: ${PIPELINE_JOB_NAME}"
  echo "Pipeline script path: ${PIPELINE_SCRIPT_PATH}"
}

print_instance_urls() {
  echo "Jenkins instance URLs:"
  echo "  jenkins-prod: $(instance_base_url "prod")"
  echo "  jenkins-dev:  $(instance_base_url "dev")"
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
