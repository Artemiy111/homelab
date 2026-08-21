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

# Креды scrape-целей с аутентификацией: единственный источник — .env
# соответствующего сервиса; netdata получает их копию с префиксом NETDATA_.
read_env_key() {
  local file="$repo_root/$1" key="$2"
  sed -n "s/^${key}=//p" "$file" 2>/dev/null | head -1
}

upsert_env "$repo_root/netdata/.env" NETDATA_NAVIDROME_METRICS_PATH \
  "$(read_env_key navidrome/.env NAVIDROME_METRICS_PATH)"
upsert_env "$repo_root/netdata/.env" NETDATA_DAWARICH_METRICS_USERNAME \
  "$(read_env_key dawarich/.env DAWARICH_METRICS_USERNAME)"
upsert_env "$repo_root/netdata/.env" NETDATA_DAWARICH_METRICS_PASSWORD \
  "$(read_env_key dawarich/.env DAWARICH_METRICS_PASSWORD)"
upsert_env "$repo_root/netdata/.env" NETDATA_FORGEJO_METRICS_TOKEN \
  "$(read_env_key forgejo/.env FORGEJO_METRICS_TOKEN)"

compose_config "$repo_root/netdata"
