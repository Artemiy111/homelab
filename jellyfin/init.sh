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

compose_config "$repo_root/jellyfin"
