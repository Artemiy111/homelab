#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0750 \
  "$APPS_STORAGE_PATH"/netdata/config \
  "$APPS_STORAGE_PATH"/netdata/lib \
  "$APPS_STORAGE_PATH"/netdata/cache

write_env_file "$repo_root/netdata/.env" <<EOF
NETDATA_HOST=netdata.$DOMAIN
EOF

compose_config "$repo_root/netdata"
