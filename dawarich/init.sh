#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p \
  "$APPS_STORAGE_PATH"/dawarich/backups \
  "$APPS_STORAGE_PATH"/dawarich/postgresql \
  "$APPS_STORAGE_PATH"/dawarich/public \
  "$APPS_STORAGE_PATH"/dawarich/redis \
  "$APPS_STORAGE_PATH"/dawarich/shared \
  "$APPS_STORAGE_PATH"/dawarich/storage \
  "$APPS_STORAGE_PATH"/dawarich/watched

write_env_file "$repo_root/dawarich/.env" <<EOF
DAWARICH_HOST=dawarich.$DOMAIN
DAWARICH_VERSION=1.11.0
POSTGRES_DB=dawarich_production
POSTGRES_USER=dawarich
POSTGRES_PASSWORD=$(random_secret)
SECRET_KEY_BASE=$(openssl rand -hex 64)
WEB_CONCURRENCY=1
BACKGROUND_PROCESSING_CONCURRENCY=3
APP_CPU_LIMIT=0.50
APP_MEMORY_LIMIT=4G
LOG_MAX_SIZE=100m
LOG_MAX_FILE=5
EOF

# Basic auth для Prometheus-метрик (см. compose.yaml); пароль генерируется
# однократно и хранится в .env.
upsert_env "$repo_root/dawarich/.env" DAWARICH_METRICS_USERNAME "netdata"
ensure_secret "$repo_root/dawarich/.env" DAWARICH_METRICS_PASSWORD >/dev/null

compose_config "$repo_root/dawarich"
