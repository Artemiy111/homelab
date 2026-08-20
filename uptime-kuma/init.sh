#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p "$APPS_STORAGE_PATH"/uptime-kuma/data

write_env_file "$repo_root/uptime-kuma/.env" <<EOF
UPTIME_KUMA_HOST=kuma.$DOMAIN
UPTIME_KUMA_USERNAME=user
UPTIME_KUMA_PASSWORD=
EOF

compose_config "$repo_root/uptime-kuma"
