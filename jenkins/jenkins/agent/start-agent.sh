#!/usr/bin/env bash
set -euo pipefail

: "${JENKINS_URL:?JENKINS_URL is required}"
: "${JENKINS_AGENT_NAME:?JENKINS_AGENT_NAME is required}"

JENKINS_URL="${JENKINS_URL%/}/"
WORK_DIR="${JENKINS_AGENT_WORKDIR:-/home/jenkins/agent}"
MAX_RETRIES="${JENKINS_AGENT_MAX_RETRIES:-180}"
SLEEP_SECONDS="${JENKINS_AGENT_RETRY_SLEEP_SECONDS:-2}"

mkdir -p "$WORK_DIR"

CURL_ARGS=(-fsSL)
if [[ -n "${JENKINS_ADMIN_USER:-}" && -n "${JENKINS_ADMIN_PASSWORD:-}" ]]; then
  CURL_ARGS+=(-u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}")
fi

wait_for_url() {
  local url="$1"
  local attempt

  for ((attempt=1; attempt<=MAX_RETRIES; attempt++)); do
    if curl "${CURL_ARGS[@]}" "$url" >/dev/null; then
      return 0
    fi
    sleep "$SLEEP_SECONDS"
  done

  return 1
}

extract_secret() {
  local xml="$1"
  printf '%s' "$xml" \
    | grep -o '<argument>[^<]*</argument>' \
    | sed -n '1{s#<argument>##;s#</argument>##;p;}' || true
}

echo "[agent:${JENKINS_AGENT_NAME}] waiting for ${JENKINS_URL}"
wait_for_url "${JENKINS_URL}login"

JNLP_URL="${JENKINS_URL}computer/${JENKINS_AGENT_NAME}/jenkins-agent.jnlp"
SECRET=""
for ((attempt=1; attempt<=MAX_RETRIES; attempt++)); do
  XML_CONTENT="$(curl "${CURL_ARGS[@]}" "$JNLP_URL" || true)"
  SECRET="$(extract_secret "$XML_CONTENT")"

  if [[ -n "$SECRET" ]]; then
    break
  fi

  sleep "$SLEEP_SECONDS"
done

if [[ -z "$SECRET" ]]; then
  echo "[agent:${JENKINS_AGENT_NAME}] failed to fetch agent secret from ${JNLP_URL}" >&2
  exit 1
fi

ARGS=(
  -url "$JENKINS_URL"
  -name "$JENKINS_AGENT_NAME"
  -secret "$SECRET"
  -workDir "$WORK_DIR"
  -webSocket
)

if [[ -n "${JENKINS_AGENT_EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_ARGS=( ${JENKINS_AGENT_EXTRA_ARGS} )
  ARGS+=("${EXTRA_ARGS[@]}")
fi

echo "[agent:${JENKINS_AGENT_NAME}] connecting"

# Prevent /usr/local/bin/jenkins-agent from appending duplicate values sourced
# from environment variables; we pass explicit CLI args above.
unset JENKINS_URL
unset JENKINS_SECRET
unset JENKINS_AGENT_NAME
unset JENKINS_AGENT_WORKDIR
unset JENKINS_ADMIN_USER
unset JENKINS_ADMIN_PASSWORD
unset AGENT_NAME
unset AGENT_WORKDIR

exec /usr/local/bin/jenkins-agent "${ARGS[@]}"
