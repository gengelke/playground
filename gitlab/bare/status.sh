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
  echo "== GitLab status =="
  require_sudo gitlab-ctl status || true
else
  echo "gitlab-ctl not found"
fi

echo "== gitlab-runner service =="
if systemctl list-unit-files | grep -q '^gitlab-runner.service'; then
  require_sudo systemctl status gitlab-runner --no-pager || true
else
  echo "gitlab-runner service not installed"
fi
