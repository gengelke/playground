#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/env.sh
source "${SCRIPT_DIR}/../lib/env.sh"

target="${1:-all}"

collect_logs() {
  local instance="$1"
  local logs_dir

  logs_dir="$(instance_logs_dir "$instance")"
  if [[ -d "$logs_dir" ]]; then
    find "$logs_dir" -name '*.log' -print
  fi
}

case "$target" in
  all)
    mapfile -t files < <(
      collect_logs prod
      collect_logs dev
    )
    ;;
  prod|dev)
    mapfile -t files < <(collect_logs "$target")
    ;;
  *)
    echo "Unknown target '${target}'. Use all, prod, or dev." >&2
    exit 1
    ;;
esac

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No logs found"
  exit 0
fi

tail -n 200 -f "${files[@]}"
