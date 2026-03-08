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

mkdir -p "$CACHE_DIR" "$BARE_STATE_DIR"

if [[ ! -f "$JENKINS_WAR_PATH" ]]; then
  echo "Downloading Jenkins WAR"
  "$CURL_BIN" -fsSL "$JENKINS_WAR_URL" -o "$JENKINS_WAR_PATH"
fi

for instance in prod dev; do
  home_dir="$(instance_home "$instance")"
  mkdir -p "$home_dir/init.groovy.d"
  cp "$INIT_GROOVY_DIR/00-bootstrap.groovy" "$home_dir/init.groovy.d/00-bootstrap.groovy"
done

echo "Bare setup completed"
