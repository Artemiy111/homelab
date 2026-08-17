#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p /storage/apps/traefik/letsencrypt

if [[ -x /storage/apps/traefik/letsencrypt ]]; then
  if [[ ! -e /storage/apps/traefik/letsencrypt/acme.json ]]; then
    install -m 0600 /dev/null /storage/apps/traefik/letsencrypt/acme.json
  fi
else
  echo 'Пропуск: каталог Traefik ACME недоступен текущему пользователю'
fi

password="$(random_secret)"
hash="$(printf '%s' "$password" | openssl passwd -apr1 -stdin)"

write_env_file "$repo_root/traefik/.env" <<EOF
TRAEFIK_HOST=traefik.$DOMAIN
TRAEFIK_DASHBOARD_USERNAME=admin
TRAEFIK_DASHBOARD_PASSWORD=$password
TRAEFIK_DASHBOARD_USERS='admin:$hash'
RFC2136_NAMESERVER=ns1.<dns-provider>.com:53
RFC2136_TSIG_ALGORITHM=hmac-sha256.
RFC2136_TSIG_KEY=replace-with-the-<dns-provider>-tsig-key-name
RFC2136_TSIG_SECRET=replace-with-the-<dns-provider>-tsig-secret
EOF

compose_config "$repo_root/traefik"
