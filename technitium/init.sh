#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0750 \
  "$APPS_STORAGE_PATH"/technitium/etc \
  "$APPS_STORAGE_PATH"/technitium/data

write_env_file "$repo_root/technitium/.env" <<EOF
APPS_STORAGE_PATH=$APPS_STORAGE_PATH
SERVER_IP=$SERVER_IP
TZ=$TZ
TECHNITIUM_HOST=dns.$DOMAIN
TECHNITIUM_ADMIN_PASSWORD=$(random_secret)
EOF

compose_config "$repo_root/technitium"
