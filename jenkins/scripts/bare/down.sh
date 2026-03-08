#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/env.sh
source "${SCRIPT_DIR}/../lib/env.sh"

stop_pid_file() {
  local pid_file="$1"
  local pid

  if [[ ! -f "$pid_file" ]]; then
    return
  fi

  pid="$(cat "$pid_file")"
  if [[ -z "$pid" ]]; then
    rm -f "$pid_file"
    return
  fi

  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true

    for _ in {1..10}; do
      if ! kill -0 "$pid" 2>/dev/null; then
        break
      fi
      sleep 1
    done

    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
  fi

  rm -f "$pid_file"
}

if [[ ! -d "$BARE_STATE_DIR" ]]; then
  echo "No bare state found"
  exit 0
fi

while IFS= read -r -d '' pid_file; do
  stop_pid_file "$pid_file"
done < <(find "$BARE_STATE_DIR" -name '*.pid' -print0)

echo "Stopped bare Jenkins controllers and agents"
