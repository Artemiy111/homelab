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
NETDATA_NAVIDROME_METRICS_PATH="$(read_env_key "$repo_root/navidrome/.env" NAVIDROME_METRICS_PATH)"
NETDATA_DAWARICH_METRICS_USERNAME="$(read_env_key "$repo_root/dawarich/.env" DAWARICH_METRICS_USERNAME)"
NETDATA_DAWARICH_METRICS_PASSWORD="$(read_env_key "$repo_root/dawarich/.env" DAWARICH_METRICS_PASSWORD)"
NETDATA_FORGEJO_METRICS_TOKEN="$(read_env_key "$repo_root/forgejo/.env" FORGEJO_METRICS_TOKEN)"

upsert_env "$repo_root/netdata/.env" NETDATA_NAVIDROME_METRICS_PATH \
  "$NETDATA_NAVIDROME_METRICS_PATH"
upsert_env "$repo_root/netdata/.env" NETDATA_DAWARICH_METRICS_USERNAME \
  "$NETDATA_DAWARICH_METRICS_USERNAME"
upsert_env "$repo_root/netdata/.env" NETDATA_DAWARICH_METRICS_PASSWORD \
  "$NETDATA_DAWARICH_METRICS_PASSWORD"
upsert_env "$repo_root/netdata/.env" NETDATA_FORGEJO_METRICS_TOKEN \
  "$NETDATA_FORGEJO_METRICS_TOKEN"

# Рендер списка scrape-целей. go.d не подставляет переменные окружения в
# конфиги, поэтому значения запекаются на сервере; файл содержит секреты,
# хранится только в $APPS_STORAGE_PATH и в Git не попадает.
export NETDATA_NAVIDROME_METRICS_PATH NETDATA_DAWARICH_METRICS_USERNAME
export NETDATA_DAWARICH_METRICS_PASSWORD NETDATA_FORGEJO_METRICS_TOKEN
ensure_dirs 0755 "$APPS_STORAGE_PATH"/netdata/config/go.d "$APPS_STORAGE_PATH"/netdata/config/go.d/sd
render_template \
  "$repo_root/netdata/config/go.d/prometheus.conf.tpl" \
  "$APPS_STORAGE_PATH/netdata/config/go.d/prometheus.conf" \
  '\$NETDATA_NAVIDROME_METRICS_PATH \$NETDATA_DAWARICH_METRICS_USERNAME \$NETDATA_DAWARICH_METRICS_PASSWORD \$NETDATA_FORGEJO_METRICS_TOKEN'
# Файл содержит секреты; 0644 нужны, потому что плагины в контейнере работают
# под непривилегированным пользователем netdata.
chmod 644 "$APPS_STORAGE_PATH/netdata/config/go.d/prometheus.conf"

compose_config "$repo_root/netdata"
