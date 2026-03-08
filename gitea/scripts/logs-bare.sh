#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

log_dir="${ROOT_DIR}/runtime/bare/logs"
mkdir -p "$log_dir"

touch "${log_dir}/gitea.log" "${log_dir}/runner1.log" "${log_dir}/runner2.log"

tail -n 100 -f "${log_dir}/gitea.log" "${log_dir}/runner1.log" "${log_dir}/runner2.log"
