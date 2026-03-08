#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

mode="${1:-}"
out_file="${2:-}"

[[ -n "$mode" ]] || die "Usage: render-gitea-config.sh <docker|bare> <output-file>"
[[ -n "$out_file" ]] || die "Usage: render-gitea-config.sh <docker|bare> <output-file>"

gitea_http_port="${GITEA_HTTP_PORT:-3000}"
gitea_domain="${GITEA_DOMAIN:-localhost}"
gitea_root_url="${GITEA_ROOT_URL:-http://localhost:${gitea_http_port}/}"
gitea_runner_token="${GITEA_RUNNER_TOKEN:-local-runner-token-change-me}"
gitea_secret_key="${GITEA_SECRET_KEY:-local-dev-secret-key-change-me}"
gitea_internal_token="${GITEA_INTERNAL_TOKEN:-local-dev-internal-token-change-me}"
gitea_jwt_secret="${GITEA_JWT_SECRET:-local-dev-jwt-secret-change-me}"

mkdir -p "$(dirname "$out_file")"

case "$mode" in
  docker)
    cat >"$out_file" <<EOF
APP_NAME = Local Gitea
RUN_USER = git
RUN_MODE = prod

[server]
DOMAIN = ${gitea_domain}
HTTP_PORT = 3000
ROOT_URL = ${gitea_root_url}
SSH_DOMAIN = ${gitea_domain}
SSH_PORT = 22
START_SSH_SERVER = false

[database]
DB_TYPE = sqlite3
PATH = /data/gitea/gitea.db

[repository]
ROOT = /data/git/repositories

[security]
INSTALL_LOCK = true
SECRET_KEY = ${gitea_secret_key}
INTERNAL_TOKEN = ${gitea_internal_token}

[oauth2]
JWT_SECRET = ${gitea_jwt_secret}

[service]
DISABLE_REGISTRATION = true
REQUIRE_SIGNIN_VIEW = false

[actions]
ENABLED = true
DEFAULT_ACTIONS_URL = self
RUNNER_REGISTRATION_TOKEN = ${gitea_runner_token}
EOF
    ;;
  bare)
    bare_data_dir="${ROOT_DIR}/runtime/bare/gitea"
    bare_log_dir="${ROOT_DIR}/runtime/bare/logs"
    bare_repo_dir="${ROOT_DIR}/runtime/bare/repositories"
    run_user="${USER:-git}"
    cat >"$out_file" <<EOF
APP_NAME = Local Gitea
RUN_USER = ${run_user}
RUN_MODE = prod
WORK_PATH = ${bare_data_dir}

[server]
DOMAIN = ${gitea_domain}
HTTP_ADDR = 127.0.0.1
HTTP_PORT = ${gitea_http_port}
ROOT_URL = ${gitea_root_url}
START_SSH_SERVER = false

[database]
DB_TYPE = sqlite3
PATH = ${bare_data_dir}/gitea.db

[repository]
ROOT = ${bare_repo_dir}

[security]
INSTALL_LOCK = true
SECRET_KEY = ${gitea_secret_key}
INTERNAL_TOKEN = ${gitea_internal_token}

[oauth2]
JWT_SECRET = ${gitea_jwt_secret}

[service]
DISABLE_REGISTRATION = true
REQUIRE_SIGNIN_VIEW = false

[actions]
ENABLED = true
DEFAULT_ACTIONS_URL = self
RUNNER_REGISTRATION_TOKEN = ${gitea_runner_token}

[log]
MODE = console,file
ROOT_PATH = ${bare_log_dir}
EOF
    ;;
  *)
    die "Unsupported mode: $mode (expected docker or bare)"
    ;;
esac

log "Rendered Gitea config: $out_file"
