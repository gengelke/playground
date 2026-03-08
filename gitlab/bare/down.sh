#!/usr/bin/env bash
set -euo pipefail

require_sudo() {
  if [[ "$(id -u)" -ne 0 ]]; then
    sudo "$@"
  else
    "$@"
  fi
}

if command -v gitlab-ctl >/dev/null 2>&1; then
  require_sudo gitlab-ctl stop
fi

if systemctl list-unit-files | grep -q '^gitlab-runsvdir.service'; then
  require_sudo systemctl stop gitlab-runsvdir || true
fi

if systemctl list-unit-files | grep -q '^gitlab-runner.service'; then
  require_sudo systemctl stop gitlab-runner || true
fi

echo "Bare mode services stopped"
