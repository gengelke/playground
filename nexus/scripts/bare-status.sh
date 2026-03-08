#!/usr/bin/env bash
set -euo pipefail

NEXUS_PID_FILE="${NEXUS_PID_FILE:-$PWD/run/nexus.pid}"

if [[ ! -f "$NEXUS_PID_FILE" ]]; then
  echo "Nexus (bare mode): not running (no PID file)."
  exit 1
fi

pid="$(cat "$NEXUS_PID_FILE" || true)"

if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
  echo "Nexus (bare mode): running (PID $pid)."
  exit 0
fi

echo "Nexus (bare mode): not running (stale PID file: $NEXUS_PID_FILE)."
exit 1

