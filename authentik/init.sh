#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 \
  /storage/apps/authentik \
  /storage/apps/authentik/backups \
  /storage/apps/authentik/data \
  /storage/apps/authentik/postgresql

traefik_network_cidr="$(traefik_network_cidr)"

write_env_file "$repo_root/authentik/.env" <<EOF
AUTHENTIK_HOST=auth.example.net
AUTHENTIK_POSTGRESQL_DATABASE=authentik
AUTHENTIK_POSTGRESQL_USER=authentik
AUTHENTIK_POSTGRESQL_PASSWORD=$(openssl rand -base64 36 | tr -d '\n')
AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')
TRAEFIK_NETWORK_CIDR=$traefik_network_cidr
EOF

compose_config "$repo_root/authentik"
