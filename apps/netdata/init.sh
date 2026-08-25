#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

# Каталог читается плагинами внутри контейнера под непривилегированным
# пользователем netdata, поэтому без ограничения группы.
ensure_dirs 0755 \
  "$APPS_STORAGE_PATH"/netdata/config \
  "$APPS_STORAGE_PATH"/netdata/config/scripts.d
ensure_dirs 0750 \
  "$APPS_STORAGE_PATH"/netdata/lib \
  "$APPS_STORAGE_PATH"/netdata/cache

# Креды scrape-целей с аутентификацией. Источник — secrets.enc.env
# соответствующего сервиса (SOPS); публичный username dawarich — в config.env.
read_secret_key() {
  local svc="$1" key="$2"
  sops -d "$repo_root/apps/$svc/secrets.enc.env" | sed -n "s/^${key}=//p" | head -1
}
NETDATA_NAVIDROME_METRICS_PATH="$(read_secret_key navidrome NAVIDROME_METRICS_PATH)"
NETDATA_DAWARICH_METRICS_USERNAME="$(sed -n "s/^DAWARICH_METRICS_USERNAME=//p" "$repo_root/apps/dawarich/config.env" | head -1)"
NETDATA_DAWARICH_METRICS_PASSWORD="$(read_secret_key dawarich DAWARICH_METRICS_PASSWORD)"
NETDATA_FORGEJO_METRICS_TOKEN="$(read_secret_key forgejo FORGEJO_METRICS_TOKEN)"
NETDATA_TECHNITIUM_METRICS_TOKEN="$(read_secret_key technitium TECHNITIUM_METRICS_TOKEN)"
NETDATA_STALWART_METRICS_USERNAME="$(read_secret_key mailserver STALWART_METRICS_USERNAME)"
NETDATA_STALWART_METRICS_PASSWORD="$(read_secret_key mailserver STALWART_METRICS_PASSWORD)"
NETDATA_UPTIME_KUMA_METRICS_API_KEY="$(read_secret_key uptime-kuma UPTIME_KUMA_METRICS_API_KEY)"

# Рендер списка scrape-целей. go.d не подставляет переменные окружения в
# конфиги, поэтому значения запекаются на сервере; файл содержит секреты,
# хранится только в $APPS_STORAGE_PATH и в Git не попадает.
export NETDATA_NAVIDROME_METRICS_PATH NETDATA_DAWARICH_METRICS_USERNAME
export NETDATA_DAWARICH_METRICS_PASSWORD NETDATA_FORGEJO_METRICS_TOKEN
export NETDATA_TECHNITIUM_METRICS_TOKEN NETDATA_STALWART_METRICS_USERNAME
export NETDATA_STALWART_METRICS_PASSWORD
export NETDATA_UPTIME_KUMA_METRICS_API_KEY
ensure_dirs 0755 "$APPS_STORAGE_PATH"/netdata/config/go.d "$APPS_STORAGE_PATH"/netdata/config/go.d/sd
render_template \
  "$repo_root/apps/netdata/config/go.d/prometheus.tpl.conf" \
  "$APPS_STORAGE_PATH/netdata/config/go.d/prometheus.conf"
# Файл содержит секреты; 0644 нужны, потому что плагины в контейнере работают
# под непривилегированным пользователем netdata.
chmod 644 "$APPS_STORAGE_PATH/netdata/config/go.d/prometheus.conf"

compose_config "$repo_root/apps/netdata"
