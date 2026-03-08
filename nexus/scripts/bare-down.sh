#!/usr/bin/env bash
set -euo pipefail

NEXUS_PID_FILE="${NEXUS_PID_FILE:-$PWD/run/nexus.pid}"

if [[ ! -f "$NEXUS_PID_FILE" ]]; then
  echo "No PID file found at $NEXUS_PID_FILE (Nexus likely not running)."
  exit 0
fi

pid="$(cat "$NEXUS_PID_FILE" || true)"
if [[ -z "$pid" ]]; then
  rm -f "$NEXUS_PID_FILE"
  echo "PID file was empty; removed."
  exit 0
fi

if ! kill -0 "$pid" 2>/dev/null; then
  rm -f "$NEXUS_PID_FILE"
  echo "No running process for PID $pid; cleaned stale PID file."
  exit 0
fi

echo "Stopping Nexus PID $pid"
kill "$pid"

for _ in $(seq 1 20); do
  if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$NEXUS_PID_FILE"
    echo "Nexus stopped."
    exit 0
  fi
  sleep 1
done

echo "Process did not stop in time; sending SIGKILL."
kill -9 "$pid"
rm -f "$NEXUS_PID_FILE"
echo "Nexus force-stopped."

