#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p \
  "$APPS_STORAGE_PATH"/forgejo/backups \
  "$APPS_STORAGE_PATH"/forgejo/data \
  "$APPS_STORAGE_PATH"/forgejo/postgresql

traefik_network_cidr="$(traefik_network_cidr)"

write_env_file "$repo_root/forgejo/.env" <<EOF
FORGEJO_HOST=forgejo.$DOMAIN
FORGEJO_SSH_PORT=2222
FORGEJO_DEFAULT_LOCALE=$DEFAULT_LOCALE
POSTGRES_DB=forgejo
POSTGRES_USER=forgejo
POSTGRES_PASSWORD=$(random_secret)
TRAEFIK_NETWORK_CIDR=$traefik_network_cidr
EOF

# Токен для Prometheus-метрик (см. compose.yaml): без него /metrics был бы
# доступен на публичном маршруте forgejo.$DOMAIN/metrics.
upsert_env "$repo_root/forgejo/.env" FORGEJO_METRICS_TOKEN "$(random_secret)"

compose_config "$repo_root/forgejo"
