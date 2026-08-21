#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 "$APPS_STORAGE_PATH/immich/library" "$APPS_STORAGE_PATH/immich/postgres"

write_env_file "$repo_root/immich/.env" <<EOF
UPLOAD_LOCATION=$APPS_STORAGE_PATH/immich/library
DB_DATA_LOCATION=$APPS_STORAGE_PATH/immich/postgres
IMMICH_VERSION=v3
IMMICH_DOMAIN=immich.$DOMAIN
DB_PASSWORD=$(random_secret)
DB_USERNAME=postgres
DB_DATABASE_NAME=immich
EOF

# Телеметрия (Prometheus-метрики) на внутренних портах 8081/8082.
upsert_env "$repo_root/immich/.env" IMMICH_TELEMETRY_INCLUDE "all"

compose_config "$repo_root/immich"
