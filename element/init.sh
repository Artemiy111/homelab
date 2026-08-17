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
echo "[init] Generated sygnal/sygnal.yaml"

echo ""
echo "[init] All configs generated in $STORAGE_BASE"
echo "[init] Review .env, then run: docker compose up -d"
