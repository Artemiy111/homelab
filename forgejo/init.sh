#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p \
  /storage/apps/forgejo/backups \
  /storage/apps/forgejo/data \
  /storage/apps/forgejo/postgresql

traefik_network_cidr="$(traefik_network_cidr)"

write_env_file "$repo_root/forgejo/.env" <<EOF
SERVER_IP=$SERVER_IP
FORGEJO_HOST=forgejo.$DOMAIN
FORGEJO_SSH_PORT=222
POSTGRES_DB=forgejo
POSTGRES_USER=forgejo
POSTGRES_PASSWORD=$(random_secret)
TRAEFIK_NETWORK_CIDR=$traefik_network_cidr
TZ=$TZ
EOF

compose_config "$repo_root/forgejo"
