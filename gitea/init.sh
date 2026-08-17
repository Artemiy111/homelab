#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p \
  /storage/apps/gitea/backups \
  /storage/apps/gitea/data \
  /storage/apps/gitea/postgresql

traefik_network_cidr="$(traefik_network_cidr)"

write_env_file "$repo_root/gitea/.env" <<EOF
SERVER_IP=$SERVER_IP
GITEA_HOST=gitea.$DOMAIN
GITEA_SSH_PORT=2222
POSTGRES_DB=gitea
POSTGRES_USER=gitea
POSTGRES_PASSWORD=$(random_secret)
GITEA_ADMIN_USERNAME=gitea-admin
GITEA_ADMIN_PASSWORD=$(random_secret)
GITEA_ADMIN_EMAIL=gitea-admin@example.invalid
TRAEFIK_NETWORK_CIDR=$traefik_network_cidr
TZ=Asia/Yekaterinburg
EOF

compose_config "$repo_root/gitea"
