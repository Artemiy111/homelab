#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

# Migrate legacy timezone for existing installations.
if [[ -f "$repo_root/element/.env" ]]; then
  if grep -q '^TZ=Europe/Moscow$' "$repo_root/element/.env"; then
    sed -i 's/^TZ=Europe\/Moscow$/TZ=Asia\/Yekaterinburg/' "$repo_root/element/.env"
    echo "[init] Migrated TZ to Asia/Yekaterinburg"
  fi
fi

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

write_env_file "$repo_root/element/.env" <<EOF
SYNAPSE_HOST=element.$DOMAIN
SYNAPSE_SERVER_NAME=$DOMAIN
ELEMENT_HOST=element-web.$DOMAIN
LIVEKIT_HOST=element-livekit.$DOMAIN
LIVEKIT_EXTERNAL_IP=$SERVER_IP
LIVEKIT_RTC_PORT_MIN=50000
LIVEKIT_RTC_PORT_MAX=50499
TURN_PORT=3479
TURN_RELAY_MIN_PORT=21000
TURN_RELAY_MAX_PORT=21499
TURN_REALM=$DOMAIN
TURN_USER=element
POSTGRES_DB=synapse
POSTGRES_USER=synapse
POSTGRES_PASSWORD=$(random_secret)
SYNAPSE_REGISTRATION_SHARED_SECRET=$(openssl rand -hex 32)
TURN_PASSWORD=$(openssl rand -hex 32)
TURN_SECRET=$(openssl rand -hex 32)
LIVEKIT_API_KEY=$(openssl rand -hex 16)
LIVEKIT_API_SECRET=$(openssl rand -hex 32)
EOF

set -a
# shellcheck disable=SC1091
source "$repo_root/element/.env"
set +a

render_template \
  "$repo_root/element/synapse/homeserver.yaml.tmpl" \
  "$APPS_STORAGE_PATH/element/synapse/config/homeserver.yaml" \
  '\$SYNAPSE_HOST \$SYNAPSE_SERVER_NAME \$POSTGRES_USER \$POSTGRES_PASSWORD \$POSTGRES_DB \$SYNAPSE_REGISTRATION_SHARED_SECRET \$TURN_PORT \$TURN_SECRET \$LIVEKIT_HOST'

render_template \
  "$repo_root/element/livekit/config.yaml.tmpl" \
  "$APPS_STORAGE_PATH/element/livekit/config.yaml" \
  '\$LIVEKIT_RTC_PORT_MIN \$LIVEKIT_RTC_PORT_MAX \$LIVEKIT_API_KEY \$LIVEKIT_API_SECRET'

render_template \
  "$repo_root/element/turn/turnserver.conf.tmpl" \
  "$APPS_STORAGE_PATH/element/turn/turnserver.conf" \
  '\$TURN_PORT \$TURN_SECRET \$TURN_REALM \$TURN_USER \$TURN_PASSWORD \$TURN_RELAY_MIN_PORT \$TURN_RELAY_MAX_PORT'

cp "$repo_root/element/sygnal/sygnal.yaml.tmpl" \
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

compose_config "$repo_root/element"
