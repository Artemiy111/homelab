#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0755 \
  "$APPS_STORAGE_PATH"/seafile \
  "$APPS_STORAGE_PATH"/seafile/backups \
  "$APPS_STORAGE_PATH"/seafile/mysql \
  "$APPS_STORAGE_PATH"/seafile/shared

write_env_file "$repo_root/seafile/.env" <<EOF
APPS_STORAGE_PATH=$APPS_STORAGE_PATH
SEAFILE_HOST=seafile.$DOMAIN
SEAFILE_VERSION=13.0.25
TIME_ZONE=$TZ
SEAFILE_SERVER_HOSTNAME=seafile.$DOMAIN
SEAFILE_SERVER_PROTOCOL=https
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
EOF

seafile_env="$repo_root/seafile/.env"
if ! grep -q '^JWT_PRIVATE_KEY=' "$seafile_env"; then
  printf 'JWT_PRIVATE_KEY=%s\n' "$(openssl rand -hex 32)" >>"$seafile_env"
  chmod 600 "$seafile_env"
  echo "Добавлен JWT_PRIVATE_KEY в $seafile_env"
fi

compose_config "$repo_root/seafile"
