#!/usr/bin/env bash
set -euo pipefail

preferred_port="${1:-8083}"

if ! [[ "$preferred_port" =~ ^[0-9]+$ ]]; then
  echo "Invalid port: '$preferred_port'" >&2
  exit 1
fi

if (( preferred_port < 1 || preferred_port > 65535 )); then
  echo "Port out of range: '$preferred_port'" >&2
  exit 1
fi

is_port_free() {
  local port="$1"

  if command -v lsof >/dev/null 2>&1; then
    ! lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
    return
  fi

  if command -v ss >/dev/null 2>&1; then
    ss -ltn "sport = :$port" 2>/dev/null | awk 'NR > 1 { found = 1 } END { exit found ? 1 : 0 }'
    return
  fi

  # Last resort: TCP connect test against localhost.
  if (echo >/dev/tcp/127.0.0.1/"$port") >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

if is_port_free "$preferred_port"; then
  echo "$preferred_port"
  exit 0
fi

if (( preferred_port == 8081 )) && is_port_free 18081; then
  echo "Port 8081 is in use; using 18081." >&2
  echo "18081"
  exit 0
fi

candidate=$((preferred_port + 1))
while (( candidate <= 65535 )); do
  if is_port_free "$candidate"; then
    echo "Port $preferred_port is in use; using $candidate." >&2
    echo "$candidate"
    exit 0
  fi
  candidate=$((candidate + 1))
done

echo "No free TCP port found between $preferred_port and 65535." >&2
exit 1
