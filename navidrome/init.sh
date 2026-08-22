#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 "$APPS_STORAGE_PATH/navidrome/data" "$APPS_STORAGE_PATH/navidrome/music"

write_env_file "$repo_root/navidrome/.env" <<EOF
NAVIDROME_HOST=music.$DOMAIN
EOF

# Секретный сегмент пути Prometheus-метрик (см. compose.yaml); генерируется
# однократно и хранится в .env.
ensure_secret "$repo_root/navidrome/.env" NAVIDROME_METRICS_PATH >/dev/null

compose_config "$repo_root/navidrome"
