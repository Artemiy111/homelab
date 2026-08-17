#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p /storage/apps/pihole/etc-pihole

write_env_file "$repo_root/pihole/.env" <<EOF
PIHOLE_HOST=pihole.example.net
PIHOLE_ADMIN_PASSWORD=$(random_secret)
EOF

compose_config "$repo_root/pihole"
