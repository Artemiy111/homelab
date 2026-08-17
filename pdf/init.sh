#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p \
  /storage/apps/pdf/configs \
  /storage/apps/pdf/customFiles \
  /storage/apps/pdf/logs \
  /storage/apps/pdf/pipeline \
  /storage/apps/pdf/tessdata

write_env_file "$repo_root/pdf/.env" <<EOF
PDF_HOST=pdf.$DOMAIN
PDF_ADMIN_USERNAME=admin
PDF_ADMIN_PASSWORD=$(random_secret)
PDF_DEFAULT_LOCALE=ru-RU
EOF

compose_config "$repo_root/pdf"
