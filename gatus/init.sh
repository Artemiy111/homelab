#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0750 \
  /storage/apps/gatus \
  /storage/apps/gatus/data

write_env_file "$repo_root/gatus/.env" <<EOF
GATUS_HOST=uptime.example.net
NTFY_TOPIC=gatus-$(openssl rand -hex 16)
# Telegram-бот (@BotFather): заполните токен и ID чата (у группы ID отрицательный)
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
EOF

compose_config "$repo_root/gatus"
