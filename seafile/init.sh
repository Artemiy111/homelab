#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0755 \
  "$APPS_STORAGE_PATH"/seafile \
  "$APPS_STORAGE_PATH"/seafile/backups \
  "$APPS_STORAGE_PATH"/seafile/mysql \
  "$APPS_STORAGE_PATH"/seafile/shared \
  "$APPS_STORAGE_PATH"/seafile/onlyoffice/data \
  "$APPS_STORAGE_PATH"/seafile/onlyoffice/lib \
  "$APPS_STORAGE_PATH"/seafile/onlyoffice/logs

write_env_file "$repo_root/seafile/.env" <<EOF
SEAFILE_HOST=seafile.$DOMAIN
SEAFILE_VERSION=13.0.25
TIME_ZONE=$TZ
SEAFILE_SERVER_HOSTNAME=seafile.$DOMAIN
SEAFILE_SERVER_PROTOCOL=https
CACHE_PROVIDER=redis
REDIS_HOST=redis
REDIS_PORT=6379
INIT_SEAFILE_ADMIN_EMAIL=seafile-admin@$DOMAIN
INIT_SEAFILE_ADMIN_PASSWORD=$(random_secret)
INIT_SEAFILE_MYSQL_ROOT_PASSWORD=$(random_secret)
SEAFILE_MYSQL_DB_HOST=db
SEAFILE_MYSQL_DB_PORT=3306
SEAFILE_MYSQL_DB_USER=seafile
SEAFILE_MYSQL_DB_PASSWORD=$(random_secret)
SEAFILE_MYSQL_DB_CCNET_DB_NAME=ccnet_db
SEAFILE_MYSQL_DB_SEAFILE_DB_NAME=seafile_db
SEAFILE_MYSQL_DB_SEAHUB_DB_NAME=seahub_db
JWT_PRIVATE_KEY=$(openssl rand -hex 32)
ENABLE_ONLYOFFICE=true
ONLYOFFICE_VERSION=9.3.0
ONLYOFFICE_HOST=onlyoffice.$DOMAIN
ONLYOFFICE_APIJS_URL=https://onlyoffice.$DOMAIN/web-apps/apps/api/documents/api.js
ONLYOFFICE_JWT_HEADER=Authorization
ONLYOFFICE_JWT_SECRET=$(openssl rand -hex 32)
EOF

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

compose_config "$repo_root/seafile"
