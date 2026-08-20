#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 "$APPS_STORAGE_PATH/navidrome/data" "$APPS_STORAGE_PATH/navidrome/music"

write_env_file "$repo_root/navidrome/.env" <<EOF
NAVIDROME_HOST=music.$DOMAIN
EOF

compose_config "$repo_root/navidrome"
