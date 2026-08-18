#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p \
  "$APPS_STORAGE_PATH"/pdf/configs \
  "$APPS_STORAGE_PATH"/pdf/customFiles \
  "$APPS_STORAGE_PATH"/pdf/logs \
  "$APPS_STORAGE_PATH"/pdf/pipeline \
  "$APPS_STORAGE_PATH"/pdf/tessdata

write_env_file "$repo_root/pdf/.env" <<EOF
APPS_STORAGE_PATH=$APPS_STORAGE_PATH
PDF_HOST=pdf.$DOMAIN
PDF_ADMIN_USERNAME=admin
PDF_ADMIN_PASSWORD=$(random_secret)
PDF_DEFAULT_LOCALE=$DEFAULT_LOCALE
EOF

compose_config "$repo_root/pdf"
