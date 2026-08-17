#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 \
  /storage/apps/pocket-id \
  /storage/apps/pocket-id/data

traefik_network_cidr="$(traefik_network_cidr)"

write_env_file "$repo_root/pocket-id/.env" <<EOF
POCKET_ID_HOST=pocket-id.$DOMAIN
ENCRYPTION_KEY=$(openssl rand -base64 32)
TRAEFIK_NETWORK_CIDR=$traefik_network_cidr
EOF

compose_config "$repo_root/pocket-id"
