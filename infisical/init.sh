#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

# postgres:14 монтируется в /var/lib/postgresql и повторно входит под UID 70,
# а redis:7 под UID 999, поэтому каталоги данных должны оставаться проходимыми
# (0755, а не 0700).
ensure_dirs 0755 \
  "$APPS_STORAGE_PATH"/infisical \
  "$APPS_STORAGE_PATH"/infisical/postgresql \
  "$APPS_STORAGE_PATH"/infisical/redis

postgres_password="$(random_secret)"
traefik_network_cidr="$(traefik_network_cidr)"

write_env_file "$repo_root/infisical/.env" <<EOF
APPS_STORAGE_PATH=$APPS_STORAGE_PATH
INFISICAL_HOST=infisical.$DOMAIN
INFISICAL_VERSION=latest
POSTGRES_DB=infisical
POSTGRES_USER=infisical
POSTGRES_PASSWORD=$postgres_password
ENCRYPTION_KEY=$(openssl rand -hex 16)
AUTH_SECRET=$(openssl rand -base64 32)
DB_CONNECTION_URI=postgresql://infisical:$postgres_password@postgres:5432/infisical?sslmode=disable
REDIS_URL=redis://redis:6379
SITE_URL=https://infisical.$DOMAIN
HOST=0.0.0.0
TRUSTED_PROXY_CIDRS=$traefik_network_cidr
TELEMETRY_ENABLED=false
EOF

compose_config "$repo_root/infisical"
