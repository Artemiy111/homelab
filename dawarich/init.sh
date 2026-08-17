#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p \
  /storage/apps/dawarich/backups \
  /storage/apps/dawarich/postgresql \
  /storage/apps/dawarich/public \
  /storage/apps/dawarich/redis \
  /storage/apps/dawarich/shared \
  /storage/apps/dawarich/storage \
  /storage/apps/dawarich/watched

write_env_file "$repo_root/dawarich/.env" <<EOF
DAWARICH_HOST=dawarich.example.net
DAWARICH_VERSION=1.11.0
POSTGRES_DB=dawarich_production
POSTGRES_USER=dawarich
POSTGRES_PASSWORD=$(random_secret)
SECRET_KEY_BASE=$(openssl rand -hex 64)
TZ=Asia/Yekaterinburg
WEB_CONCURRENCY=1
BACKGROUND_PROCESSING_CONCURRENCY=3
APP_CPU_LIMIT=0.50
APP_MEMORY_LIMIT=4G
LOG_MAX_SIZE=100m
LOG_MAX_FILE=5
EOF

compose_config "$repo_root/dawarich"
