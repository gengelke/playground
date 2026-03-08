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
  echo "Tailing GitLab logs (Ctrl+C to stop)"
  require_sudo gitlab-ctl tail
else
  echo "gitlab-ctl not found"
fi
