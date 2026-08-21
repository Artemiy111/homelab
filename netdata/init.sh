#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

# Каталог читается плагинами внутри контейнера под непривилегированным
# пользователем netdata, поэтому без ограничения группы.
ensure_dirs 0755 \
  "$APPS_STORAGE_PATH"/netdata/config \
  "$APPS_STORAGE_PATH"/netdata/config/scripts.d
ensure_dirs 0750 \
  "$APPS_STORAGE_PATH"/netdata/lib \
  "$APPS_STORAGE_PATH"/netdata/cache

write_env_file "$repo_root/netdata/.env" <<EOF
NETDATA_HOST=netdata.$DOMAIN
EOF

compose_config "$repo_root/netdata"
