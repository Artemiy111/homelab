#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p \
  "$APPS_STORAGE_PATH"/paperless/data \
  "$APPS_STORAGE_PATH"/paperless/media \
  "$APPS_STORAGE_PATH"/paperless/export \
  "$APPS_STORAGE_PATH"/paperless/consume \
  "$APPS_STORAGE_PATH"/paperless/postgresql \
  "$APPS_STORAGE_PATH"/paperless/redis

write_env_file "$repo_root/paperless/.env" <<EOF
APPS_STORAGE_PATH=$APPS_STORAGE_PATH
PAPERLESS_HOST=paperless.$DOMAIN
PAPERLESS_SECRET_KEY=$(random_secret)
POSTGRES_DB=paperless
POSTGRES_USER=paperless
POSTGRES_PASSWORD=$(random_secret)
PAPERLESS_OCR_LANGUAGE=rus
PAPERLESS_OCR_LANGUAGES=rus
USERMAP_UID=1000
USERMAP_GID=1000
EOF

compose_config "$repo_root/paperless"
