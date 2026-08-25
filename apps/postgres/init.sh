#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 \
  "$APPS_STORAGE_PATH"/postgres

# PostgreSQL 18 restarts its entrypoint as UID 70 after preparing the versioned
# PGDATA directory. It needs execute permission to traverse this bind mount.
ensure_dirs 0711 \
  "$APPS_STORAGE_PATH"/postgres/data

compose_config "$repo_root/apps/postgres"
