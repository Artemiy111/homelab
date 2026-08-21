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

seafile_env="$repo_root/seafile/.env"
if ! grep -q '^JWT_PRIVATE_KEY=' "$seafile_env"; then
  printf 'JWT_PRIVATE_KEY=%s\n' "$(openssl rand -hex 32)" >>"$seafile_env"
  chmod 600 "$seafile_env"
  echo "Добавлен JWT_PRIVATE_KEY в $seafile_env"
fi

if ! grep -q '^CACHE_PROVIDER=' "$seafile_env"; then
  cat >>"$seafile_env" <<'EOF'
CACHE_PROVIDER=redis
REDIS_HOST=redis
REDIS_PORT=6379
EOF
  chmod 600 "$seafile_env"
  echo "Добавлена конфигурация Redis в $seafile_env"
fi

if ! grep -q '^ONLYOFFICE_JWT_SECRET=' "$seafile_env"; then
  printf 'ONLYOFFICE_JWT_SECRET=%s\n' "$(openssl rand -hex 32)" >>"$seafile_env"
  chmod 600 "$seafile_env"
  echo "Добавлен секрет OnlyOffice в $seafile_env"
fi

if ! grep -q '^ENABLE_ONLYOFFICE=' "$seafile_env"; then
  cat >>"$seafile_env" <<EOF
ENABLE_ONLYOFFICE=true
ONLYOFFICE_VERSION=9.3.0
ONLYOFFICE_HOST=onlyoffice.$DOMAIN
ONLYOFFICE_APIJS_URL=https://onlyoffice.$DOMAIN/web-apps/apps/api/documents/api.js
ONLYOFFICE_JWT_HEADER=Authorization
EOF
  chmod 600 "$seafile_env"
  echo "Добавлена конфигурация OnlyOffice в $seafile_env"
fi

apply_onlyoffice_settings() {
  local settings_path=/shared/seafile/conf/seahub_settings.py
  local office_api_url office_jwt_header office_jwt_secret

  if ! docker inspect --format '{{.State.Running}}' seafile 2>/dev/null | grep -qx true; then
    return 0
  fi

  office_api_url="$(sed -n 's/^ONLYOFFICE_APIJS_URL=//p' "$seafile_env" | tail -n 1)"
  office_jwt_header="$(sed -n 's/^ONLYOFFICE_JWT_HEADER=//p' "$seafile_env" | tail -n 1)"
  office_jwt_secret="$(sed -n 's/^ONLYOFFICE_JWT_SECRET=//p' "$seafile_env" | tail -n 1)"

  docker exec \
    -e "ONLYOFFICE_APIJS_URL=$office_api_url" \
    -e "ONLYOFFICE_JWT_HEADER=$office_jwt_header" \
    -e "ONLYOFFICE_JWT_SECRET=$office_jwt_secret" \
    seafile sh -eu -c '
      if [ -f "$1" ]; then
        sed -i "/^# BEGIN HOMELAB ONLYOFFICE$/,/^# END HOMELAB ONLYOFFICE$/d; /^ENABLE_ONLYOFFICE =/d; /^ONLYOFFICE_APIJS_URL =/d; /^ONLYOFFICE_JWT_HEADER =/d; /^ONLYOFFICE_JWT_SECRET =/d" "$1"
        printf "\n# BEGIN HOMELAB ONLYOFFICE\nENABLE_ONLYOFFICE = True\nONLYOFFICE_APIJS_URL = \047%s\047\nONLYOFFICE_JWT_HEADER = \047%s\047\nONLYOFFICE_JWT_SECRET = \047%s\047\n# END HOMELAB ONLYOFFICE\n" "$ONLYOFFICE_APIJS_URL" "$ONLYOFFICE_JWT_HEADER" "$ONLYOFFICE_JWT_SECRET" >>"$1"
        echo "Обновлены настройки OnlyOffice в $1"
      fi
    ' sh "$settings_path"
}

compose_config "$repo_root/seafile"
apply_onlyoffice_settings
