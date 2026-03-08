#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

pid_dir="${ROOT_DIR}/runtime/bare/pids"
mkdir -p "$pid_dir"

stop_pid_file "${pid_dir}/runner2.pid" "runner2"
stop_pid_file "${pid_dir}/runner1.pid" "runner1"
stop_pid_file "${pid_dir}/gitea.pid" "gitea"

log "Bare mode stopped"
