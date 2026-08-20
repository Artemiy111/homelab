#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 "$APPS_STORAGE_PATH/lute/data" "$APPS_STORAGE_PATH/lute/books"

write_env_file "$repo_root/lute/.env" <<EOF
LUTE_HOST=lute.$DOMAIN
EOF

compose_config "$repo_root/lute"
