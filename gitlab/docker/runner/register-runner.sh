#!/bin/sh
set -eu

CONFIG_FILE="${RUNNER_CONFIG_FILE:-/etc/gitlab-runner/config.toml}"
RUNNER_NAME="${RUNNER_NAME:-gitlab-worker}"
RUNNER_TAG_LIST="${RUNNER_TAG_LIST:-docker}"
RUNNER_GITLAB_URL="${RUNNER_GITLAB_URL:-http://gitlab:8929}"
RUNNER_EXECUTOR="${RUNNER_EXECUTOR:-docker}"
RUNNER_DOCKER_IMAGE="${RUNNER_DOCKER_IMAGE:-alpine:3.20}"
RUNNER_LOCKED="${RUNNER_LOCKED:-false}"
RUNNER_RUN_UNTAGGED="${RUNNER_RUN_UNTAGGED:-true}"

register_args="--non-interactive --config ${CONFIG_FILE} --url ${RUNNER_GITLAB_URL} --executor ${RUNNER_EXECUTOR} --description ${RUNNER_NAME} --tag-list ${RUNNER_TAG_LIST} --locked=${RUNNER_LOCKED} --run-untagged=${RUNNER_RUN_UNTAGGED}"

if [ "${RUNNER_EXECUTOR}" = "docker" ]; then
  register_args="${register_args} --docker-image ${RUNNER_DOCKER_IMAGE}"
fi

mkdir -p "$(dirname "${CONFIG_FILE}")"

if [ -f "${CONFIG_FILE}" ] && grep -q "name = \"${RUNNER_NAME}\"" "${CONFIG_FILE}"; then
  echo "Runner ${RUNNER_NAME} already present in config."
else
  auth_mode=""
  if [ -n "${RUNNER_TOKEN:-}" ]; then
    auth_mode="token"
    register_args="${register_args} --token ${RUNNER_TOKEN}"
  elif [ -n "${RUNNER_REGISTRATION_TOKEN:-}" ]; then
    auth_mode="registration-token"
    register_args="${register_args} --registration-token ${RUNNER_REGISTRATION_TOKEN}"
  else
    echo "No runner auth provided. Set RUNNER_1_TOKEN/RUNNER_2_TOKEN or RUNNER_REGISTRATION_TOKEN."
    exit 1
  fi

  echo "Registering ${RUNNER_NAME} using ${auth_mode}..."
  n=0
  until gitlab-runner register ${register_args}; do
    n=$((n + 1))
    if [ "$n" -ge 60 ]; then
      echo "Runner registration failed after ${n} attempts."
      exit 1
    fi
    echo "GitLab not ready yet for ${RUNNER_NAME}; retrying in 10s..."
    sleep 10
  done
fi

echo "Starting gitlab-runner process for ${RUNNER_NAME}"
exec gitlab-runner run --working-directory /home/gitlab-runner --config "${CONFIG_FILE}"
