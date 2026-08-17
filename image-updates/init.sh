#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p /storage/apps/wud/store

write_env_file "$repo_root/image-updates/.env" <<EOF
TZ=$TZ
WUD_HOST=wud.$DOMAIN
CUP_HOST=cup.$DOMAIN
EOF

compose_config "$repo_root/image-updates"
