#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

write_env_file "$repo_root/oauth2-proxy/.env" <<EOF
ZITADEL_HOST=id.$DOMAIN
OAUTH2_PROXY_HOST=oauth.$DOMAIN
DOMAIN=$DOMAIN
OAUTH2_PROXY_CLIENT_ID=replace-with-zitadel-client-id
OAUTH2_PROXY_CLIENT_SECRET=replace-with-zitadel-client-secret
OAUTH2_PROXY_COOKIE_SECRET=$(openssl rand -base64 32 | tr -d '\n' | tr '+/' '-_')
OAUTH2_PROXY_VERSION=v7.15.0
EOF

compose_config "$repo_root/oauth2-proxy"
