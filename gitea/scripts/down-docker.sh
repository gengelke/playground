#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_cmd docker

compose_file="${ROOT_DIR}/docker-compose.yml"

log "Stopping docker mode services"
docker compose -f "$compose_file" down
log "Docker mode stopped"
