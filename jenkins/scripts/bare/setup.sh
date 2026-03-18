#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/env.sh
source "${SCRIPT_DIR}/../lib/env.sh"

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

require_command "$JAVA_BIN"
require_command "$CURL_BIN"

java_major="$("$JAVA_BIN" -version 2>&1 | sed -nE '1{s/.* version "([0-9]+).*/\1/p}')"
if [[ -z "$java_major" || "$java_major" -lt 21 ]]; then
  echo "Java 21+ is required for Jenkins bare mode. Detected: ${java_major:-unknown}" >&2
  exit 1
fi

mkdir -p "$CACHE_DIR" "$BARE_STATE_DIR"

if [[ ! -f "$JENKINS_WAR_PATH" ]]; then
  echo "Downloading Jenkins WAR"
  "$CURL_BIN" -fsSL "$JENKINS_WAR_URL" -o "$JENKINS_WAR_PATH"
fi

for instance in prod dev; do
  home_dir="$(instance_home "$instance")"
  mkdir -p "$home_dir/init.groovy.d"
  mkdir -p "$home_dir/scriptler/scripts"
  cp "$INIT_GROOVY_DIR/00-bootstrap.groovy" "$home_dir/init.groovy.d/00-bootstrap.groovy"
  cp "${ROOT_DIR}/controller/scriptler/scripts/employee-selection.groovy" "$home_dir/scriptler/scripts/employee-selection.groovy"
done

echo "Bare setup completed"
