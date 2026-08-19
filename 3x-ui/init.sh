#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 \
  "$APPS_STORAGE_PATH"/3x-ui \
  "$APPS_STORAGE_PATH"/3x-ui/db \
  "$APPS_STORAGE_PATH"/3x-ui/log

write_env_file "$repo_root/3x-ui/.env" <<EOF
APPS_STORAGE_PATH=$APPS_STORAGE_PATH
SERVER_IP=$SERVER_IP
TZ=$TZ
XUI_HOST=xui.$DOMAIN
XUI_ADMIN_USERNAME=xui-admin
XUI_ADMIN_PASSWORD=$(random_secret)
XUI_WEB_BASE_PATH=/panel-$(openssl rand -hex 12)/
XUI_INBOUND_PORT=8443
XUI_EGRESS_PORT=8440
EOF

compose_config "$repo_root/3x-ui"
