#!/usr/bin/env bash
set -euo pipefail

NEXUS_DIST_URL="${NEXUS_DIST_URL:?NEXUS_DIST_URL is required}"
NEXUS_BASE_DIR="${NEXUS_BASE_DIR:-$PWD/.local}"
NEXUS_DATA_DIR="${NEXUS_DATA_DIR:-$PWD/data/bare-data}"
NEXUS_LOG_FILE="${NEXUS_LOG_FILE:-$PWD/logs/bare/nexus.log}"
NEXUS_PID_FILE="${NEXUS_PID_FILE:-$PWD/run/nexus.pid}"
NEXUS_HTTP_PORT="${NEXUS_HTTP_PORT:-8083}"

mkdir -p "$NEXUS_BASE_DIR" "$NEXUS_DATA_DIR" "$(dirname "$NEXUS_LOG_FILE")" "$(dirname "$NEXUS_PID_FILE")"

archive="$NEXUS_BASE_DIR/nexus-unix.tar.gz"

if [[ -f "$NEXUS_PID_FILE" ]]; then
  old_pid="$(cat "$NEXUS_PID_FILE" || true)"
  if [[ -n "${old_pid}" ]] && kill -0 "$old_pid" 2>/dev/null; then
    echo "Nexus is already running with PID $old_pid"
    exit 0
  fi
fi

if [[ ! -f "$archive" ]]; then
  echo "Downloading Nexus from $NEXUS_DIST_URL"
  curl -fsSL "$NEXUS_DIST_URL" -o "$archive"
fi

nexus_home=""
existing_home="$(find "$NEXUS_BASE_DIR" -maxdepth 1 -mindepth 1 -type d -name 'nexus-*' | head -n1 || true)"
if [[ -n "$existing_home" ]]; then
  nexus_home="$existing_home"
else
  echo "Extracting Nexus archive"
  tar -xzf "$archive" -C "$NEXUS_BASE_DIR"
  nexus_home="$(find "$NEXUS_BASE_DIR" -maxdepth 1 -mindepth 1 -type d -name 'nexus-*' | head -n1 || true)"
fi

if [[ -z "$nexus_home" ]]; then
  echo "Could not determine Nexus installation directory under $NEXUS_BASE_DIR" >&2
  exit 1
fi

export NEXUS_DATA="$NEXUS_DATA_DIR"

properties_file="$NEXUS_DATA_DIR/etc/nexus.properties"
mkdir -p "$(dirname "$properties_file")"
if [[ -f "$properties_file" ]]; then
  if grep -q '^application-port=' "$properties_file"; then
    awk -v port="$NEXUS_HTTP_PORT" '
      /^application-port=/ { print "application-port=" port; found=1; next }
      { print }
      END { if (!found) print "application-port=" port }
    ' "$properties_file" >"${properties_file}.tmp"
    mv "${properties_file}.tmp" "$properties_file"
  else
    printf '\napplication-port=%s\n' "$NEXUS_HTTP_PORT" >>"$properties_file"
  fi
else
  printf 'application-port=%s\n' "$NEXUS_HTTP_PORT" >"$properties_file"
fi

echo "Starting Nexus from $nexus_home"
nohup "$nexus_home/bin/nexus" run >>"$NEXUS_LOG_FILE" 2>&1 &
echo $! >"$NEXUS_PID_FILE"

echo "Nexus started in bare mode (PID $(cat "$NEXUS_PID_FILE"))."
echo "Logs: $NEXUS_LOG_FILE"
