#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/env.sh
source "${SCRIPT_DIR}/../lib/env.sh"

print_status() {
  local instance="$1"
  local controller_pid_file controller_state base_url pid_file

  controller_pid_file="$(instance_controller_pid_file "$instance")"
  base_url="$(instance_base_url "$instance")"

  if is_pid_running "$controller_pid_file"; then
    controller_state="running (pid $(cat "$controller_pid_file"))"
  else
    controller_state="stopped"
  fi

  echo "$(instance_name "$instance")"
  echo "  url: ${base_url}"
  echo "  controller: ${controller_state}"

  for ((index=1; index<=AGENT_COUNT; index++)); do
    pid_file="$(agent_pid_file "$instance" "$index")"
    if is_pid_running "$pid_file"; then
      echo "  agent ${index}: running (pid $(cat "$pid_file"))"
    else
      echo "  agent ${index}: stopped"
    fi
  done
}

print_status prod
print_status dev
