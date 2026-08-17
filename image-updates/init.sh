#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p /storage/apps/wud/store

write_env_file "$repo_root/image-updates/.env" <<EOF
WUD_HOST=wud.example.net
CUP_HOST=cup.example.net
EOF

compose_config "$repo_root/image-updates"
