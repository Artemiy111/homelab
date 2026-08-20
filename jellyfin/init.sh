#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p \
  "$APPS_STORAGE_PATH"/jellyfin/config \
  "$APPS_STORAGE_PATH"/jellyfin/cache

render_group_id="$(getent group render | cut -d: -f3)"
if [[ -z "$render_group_id" ]]; then
  echo 'Не найдена группа render для Jellyfin' >&2
  exit 1
fi

write_env_file "$repo_root/jellyfin/.env" <<EOF
JELLYFIN_HOST=jellyfin.$DOMAIN
JELLYFIN_RENDER_GROUP_ID=$render_group_id
EOF

compose_config "$repo_root/jellyfin"
