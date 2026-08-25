#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0755 \
  "$APPS_STORAGE_PATH"/seafile \
  "$APPS_STORAGE_PATH"/seafile/backups \
  "$APPS_STORAGE_PATH"/seafile/mysql \
  "$APPS_STORAGE_PATH"/seafile/shared \
  "$APPS_STORAGE_PATH"/seafile/onlyoffice/data \
  "$APPS_STORAGE_PATH"/seafile/onlyoffice/lib \
  "$APPS_STORAGE_PATH"/seafile/onlyoffice/logs

# Конфигурация и секреты приходят через окружение: bootstrap подмешивает
# config.env и расшифровывает secrets.enc.env (sops exec-env). Plaintext .env
# не создаётся.

# Подключаем seahub_onlyoffice.py (примонтирован в compose.yaml) к настройкам
# Seahub. Файл настроек создаёт контейнер от root, поэтому дописываем через
# docker exec. Однократная операция: при следующих запусках строка уже есть.
if docker inspect --format '{{.State.Running}}' seafile 2>/dev/null | grep -qx true; then
  docker exec seafile sh -c '
    test -f "$1" || exit 0
    grep -q "BEGIN HOMELAB ONLYOFFICE" "$1" && exit 0
    printf "\n# BEGIN HOMELAB ONLYOFFICE\nexec(open(\"/shared/seafile/conf/seahub_onlyoffice.py\").read())\n# END HOMELAB ONLYOFFICE\n" >>"$1"
    echo "Подключён seahub_onlyoffice.py — перезапустите seafile"
  ' sh /shared/seafile/conf/seahub_settings.py
fi

compose_config "$repo_root/apps/seafile"
