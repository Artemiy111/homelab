#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p \
  "$APPS_STORAGE_PATH"/nextcloud/backups \
  "$APPS_STORAGE_PATH"/nextcloud/html \
  "$APPS_STORAGE_PATH"/nextcloud/postgresql \
  "$APPS_STORAGE_PATH"/nextcloud/redis

traefik_network_cidr="$(traefik_network_cidr)"

write_env_file "$repo_root/nextcloud/.env" <<EOF
APPS_STORAGE_PATH=$APPS_STORAGE_PATH
NEXTCLOUD_HOST=nextcloud.$DOMAIN
NEXTCLOUD_ADMIN_USER=nextcloud-admin
NEXTCLOUD_ADMIN_PASSWORD=$(random_secret)
POSTGRES_DB=nextcloud
POSTGRES_USER=nextcloud
POSTGRES_PASSWORD=$(random_secret)
TRAEFIK_NETWORK_CIDR=$traefik_network_cidr
TZ=$TZ
EOF

compose_config "$repo_root/nextcloud"
