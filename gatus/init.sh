#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0750 \
  "$APPS_STORAGE_PATH"/gatus \
  "$APPS_STORAGE_PATH"/gatus/data

write_env_file "$repo_root/gatus/.env" <<EOF
APPS_STORAGE_PATH=$APPS_STORAGE_PATH
SERVER_IP=$SERVER_IP
GATUS_HOST=uptime.$DOMAIN
DOMAIN=$DOMAIN
NTFY_TOPIC=gatus-$(openssl rand -hex 16)
# Telegram-бот (@BotFather): заполните токен и ID чата (у группы ID отрицательный)
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
TELEGRAM_PROXY_URL=http://$SERVER_IP:8440
EOF

compose_config "$repo_root/gatus"
