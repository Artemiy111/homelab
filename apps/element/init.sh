#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 \
  "$APPS_STORAGE_PATH/element/synapse/data" \
  "$APPS_STORAGE_PATH/element/synapse/config" \
  "$APPS_STORAGE_PATH/element/synapse/media_store" \
  "$APPS_STORAGE_PATH/element/postgresql-16" \
  "$APPS_STORAGE_PATH/element/redis" \
  "$APPS_STORAGE_PATH/element/livekit" \
  "$APPS_STORAGE_PATH/element/turn" \
  "$APPS_STORAGE_PATH/element/sygnal"

traefik_network_cidr="$(traefik_network_cidr)"

# Конфиг браузерного Element Web рендерится из шаблона: домен приходит
# из DOMAIN (common.sh), готовый файл в Git не попадает.
render_template \
  "$repo_root/apps/element/element-web/config.tpl.json" \
  "$repo_root/apps/element/element-web/config.json"

# Конфигурация и секреты приходят через окружение: bootstrap подмешивает
# config.env и расшифровывает secrets.enc.env (через service_run). Plaintext .env
# не создаётся.

traefik_network_cidr="$(traefik_network_cidr)"

render_template \
  "$repo_root/apps/element/synapse/homeserver.tpl.yaml" \
  "$APPS_STORAGE_PATH/element/synapse/config/homeserver.yaml"


render_template \
  "$repo_root/apps/element/livekit/config.tpl.yaml" \
  "$APPS_STORAGE_PATH/element/livekit/config.yaml"


render_template \
  "$repo_root/apps/element/turn/turnserver.tpl.conf" \
  "$APPS_STORAGE_PATH/element/turn/turnserver.conf"


cp "$repo_root/apps/element/sygnal/sygnal.tpl.yaml" \
  "$APPS_STORAGE_PATH/element/sygnal/sygnal.yaml"

if [[ -n "${FCM_SERVER_KEY:-}" ]]; then
  cat >> "$APPS_STORAGE_PATH/element/sygnal/sygnal.yaml" <<YAML

apps:
  "io.element":
    type: gcm
    api_key: "${FCM_SERVER_KEY}"
YAML
else
  printf '\napps: {}\n' >> "$APPS_STORAGE_PATH/element/sygnal/sygnal.yaml"
fi

compose_config "$repo_root/apps/element"
