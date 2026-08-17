#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p "$APPS_STORAGE_PATH"/traefik/letsencrypt

if [[ -x "$APPS_STORAGE_PATH"/traefik/letsencrypt ]]; then
  if [[ ! -e "$APPS_STORAGE_PATH"/traefik/letsencrypt/acme.json ]]; then
    install -m 0600 /dev/null "$APPS_STORAGE_PATH"/traefik/letsencrypt/acme.json
  fi
else
  echo 'Пропуск: каталог Traefik ACME недоступен текущему пользователю'
fi

password="$(random_secret)"
hash="$(printf '%s' "$password" | openssl passwd -apr1 -stdin)"

write_env_file "$repo_root/traefik/.env" <<EOF
APPS_STORAGE_PATH=$APPS_STORAGE_PATH
SERVER_IP=$SERVER_IP
TRAEFIK_HOST=traefik.$DOMAIN
TRAEFIK_DASHBOARD_USERNAME=admin
TRAEFIK_DASHBOARD_PASSWORD=$password
TRAEFIK_DASHBOARD_USERS='admin:$hash'
RFC2136_NAMESERVER=ns1.<dns-provider>.com:53
RFC2136_TSIG_ALGORITHM=hmac-sha256.
RFC2136_TSIG_KEY=replace-with-the-<dns-provider>-tsig-key-name
RFC2136_TSIG_SECRET=replace-with-the-<dns-provider>-tsig-secret
LETSENCRYPT_EMAIL=
EOF

# write_env_file пропускает уже существующий .env, поэтому читаем email из него
# и запекаем в статический конфиг Traefik (env-подстановка в нём не работает).
LETSENCRYPT_EMAIL="$(sed -n 's/^LETSENCRYPT_EMAIL=//p' "$repo_root/traefik/.env")"
LETSENCRYPT_EMAIL="$LETSENCRYPT_EMAIL" render_template \
  "$repo_root/traefik/traefik.yaml.tpl" \
  "$repo_root/traefik/traefik.yaml" \
  '\$DOMAIN \$LETSENCRYPT_EMAIL'

compose_config "$repo_root/traefik"
