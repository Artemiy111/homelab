#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0755 \
  "$APPS_STORAGE_PATH"/seafile \
  "$APPS_STORAGE_PATH"/seafile/backups \
  "$APPS_STORAGE_PATH"/seafile/shared \
  "$APPS_STORAGE_PATH"/seafile/onlyoffice/data \
  "$APPS_STORAGE_PATH"/seafile/onlyoffice/lib \
  "$APPS_STORAGE_PATH"/seafile/onlyoffice/logs

# init.sh выполняется ДО `docker compose up -d` (создаёт каталоги хранилища и
# проверяет Compose-конфигурацию). Всё, что требует уже запущенного контейнера
# Seafile (подключение seahub_onlyoffice.py / seahub_oauth.py в seahub_settings.py),
# вынесено в отдельный скрипт init-postinstall.sh, который запускают ПОСЛЕ `up -d`.

compose_config "$repo_root/apps/seafile"
