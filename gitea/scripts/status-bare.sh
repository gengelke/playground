#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

pid_dir="${ROOT_DIR}/runtime/bare/pids"

print_status() {
  local name="$1"
  local pid_file="$2"

  if [[ -f "$pid_file" ]]; then
    local pid
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if is_pid_running "$pid"; then
      printf "%-10s running (pid %s)\n" "$name" "$pid"
      return 0
    fi
  fi

  printf "%-10s stopped\n" "$name"
}

print_status "gitea" "${pid_dir}/gitea.pid"
print_status "runner1" "${pid_dir}/runner1.pid"
print_status "runner2" "${pid_dir}/runner2.pid"
