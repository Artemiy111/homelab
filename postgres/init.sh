#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 \
  "$APPS_STORAGE_PATH"/postgres

# PostgreSQL 18 restarts its entrypoint as UID 70 after preparing the versioned
# PGDATA directory. It needs execute permission to traverse this bind mount.
ensure_dirs 0711 \
  "$APPS_STORAGE_PATH"/postgres/data

write_env_file "$repo_root/postgres/.env" <<EOF
APPS_STORAGE_PATH=$APPS_STORAGE_PATH
PGWEB_HOST=postgres.$DOMAIN
POSTGRES_DB=playground
POSTGRES_USER=playground
POSTGRES_PASSWORD=$(random_secret)
PGWEB_AUTH_USER=pgweb
PGWEB_AUTH_PASS=$(random_secret)
EOF

compose_config "$repo_root/postgres"
