#!/usr/bin/env bash
# init.sh — Generate Element/Matrix configs from .env
# Run once before first deploy

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../scripts/lib/common.sh"
STORAGE_BASE="$APPS_STORAGE_PATH/element"

if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo "ERROR: Create .env from .env.example first" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source "$SCRIPT_DIR/.env"
set +a

# Element originally used the Moscow timezone. Keep the homelab-wide default
# consistent for existing installations as well as newly generated .env files.
if [[ "${TZ:-}" == "Europe/Moscow" ]]; then
  sed -i 's/^TZ=Europe\/Moscow$/TZ=Asia\/Yekaterinburg/' "$SCRIPT_DIR/.env"
  TZ=Asia/Yekaterinburg
  export TZ
  echo "[init] Migrated TZ to Asia/Yekaterinburg"
fi

# Generate secrets if empty
ensure_secret() {
  local var_name="$1"
  local current_value="${!var_name:-}"
  if [ -z "$current_value" ]; then
    local generated
    generated=$(openssl rand -hex 32)
    echo "${var_name}=${generated}" >> "$SCRIPT_DIR/.env"
    export "$var_name=$generated"
    echo "[init] Generated ${var_name}"
  fi
}

ensure_secret SYNAPSE_REGISTRATION_SHARED_SECRET
ensure_secret POSTGRES_PASSWORD
ensure_secret TURN_PASSWORD
ensure_secret TURN_SECRET

ensure_default() {
  local var_name="$1" default_value="$2"
  if [[ -z "${!var_name:-}" ]]; then
    echo "${var_name}=${default_value}" >> "$SCRIPT_DIR/.env"
    printf -v "$var_name" '%s' "$default_value"
    export "$var_name"
    echo "[init] Set ${var_name}=${default_value}"
  fi
}

# Keep Element Call media ports separate from Nextcloud Talk (3478 and
# 20000-20499) and from each other. Existing .env files acquire these defaults
# on their next init without changing any secret.
ensure_default LIVEKIT_RTC_PORT_MIN 50000
ensure_default LIVEKIT_RTC_PORT_MAX 50499
ensure_default TURN_PORT 3479
ensure_default TURN_RELAY_MIN_PORT 21000
ensure_default TURN_RELAY_MAX_PORT 21499

# LiveKit keys need different lengths
if [ -z "${LIVEKIT_API_KEY:-}" ]; then
  LIVEKIT_API_KEY=$(openssl rand -hex 16)
  echo "LIVEKIT_API_KEY=${LIVEKIT_API_KEY}" >> "$SCRIPT_DIR/.env"
  echo "[init] Generated LIVEKIT_API_KEY"
fi
if [ -z "${LIVEKIT_API_SECRET:-}" ]; then
  LIVEKIT_API_SECRET=$(openssl rand -hex 32)
  echo "LIVEKIT_API_SECRET=${LIVEKIT_API_SECRET}" >> "$SCRIPT_DIR/.env"
  echo "[init] Generated LIVEKIT_API_SECRET"
fi

# Create storage directories
ensure_dirs 0700 \
  "$STORAGE_BASE/synapse/data" \
  "$STORAGE_BASE/synapse/config" \
  "$STORAGE_BASE/synapse/media_store" \
  "$STORAGE_BASE/postgresql-16" \
  "$STORAGE_BASE/redis" \
  "$STORAGE_BASE/livekit" \
  "$STORAGE_BASE/turn" \
  "$STORAGE_BASE/sygnal"

# Re-export all vars for envsubst
set -a
# shellcheck disable=SC1091
source "$SCRIPT_DIR/.env"
set +a

# Generate configs from templates
envsubst < "$SCRIPT_DIR/synapse/homeserver.yaml.tmpl" > "$STORAGE_BASE/synapse/config/homeserver.yaml"
echo "[init] Generated synapse/homeserver.yaml"

envsubst < "$SCRIPT_DIR/livekit/config.yaml.tmpl" > "$STORAGE_BASE/livekit/config.yaml"
echo "[init] Generated livekit/config.yaml"

envsubst < "$SCRIPT_DIR/turn/turnserver.conf.tmpl" > "$STORAGE_BASE/turn/turnserver.conf"
echo "[init] Generated turn/turnserver.conf"

envsubst < "$SCRIPT_DIR/sygnal/sygnal.yaml.tmpl" > "$STORAGE_BASE/sygnal/sygnal.yaml"
if [[ -n "${FCM_SERVER_KEY:-}" ]]; then
  cat >> "$STORAGE_BASE/sygnal/sygnal.yaml" <<EOF

apps:
  "io.element":
    type: gcm
    api_key: "${FCM_SERVER_KEY}"
EOF
else
  printf '\napps: {}\n' >> "$STORAGE_BASE/sygnal/sygnal.yaml"
fi
echo "[init] Generated sygnal/sygnal.yaml"

echo ""
echo "[init] All configs generated in $STORAGE_BASE"
echo "[init] Review .env, then run: docker compose up -d"
