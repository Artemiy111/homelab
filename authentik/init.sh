#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 \
  "$APPS_STORAGE_PATH"/authentik \
  "$APPS_STORAGE_PATH"/authentik/backups \
  "$APPS_STORAGE_PATH"/authentik/data \
  "$APPS_STORAGE_PATH"/authentik/postgresql

traefik_network_cidr="$(traefik_network_cidr)"

write_env_file "$repo_root/authentik/.env" <<EOF
AUTHENTIK_HOST=auth.$DOMAIN
AUTHENTIK_POSTGRESQL_DATABASE=authentik
AUTHENTIK_POSTGRESQL_USER=authentik
AUTHENTIK_POSTGRESQL_PASSWORD=$(openssl rand -base64 36 | tr -d '\n')
AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')
TRAEFIK_NETWORK_CIDR=$traefik_network_cidr
EOF

compose_config "$repo_root/authentik"
