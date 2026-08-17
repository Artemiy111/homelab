#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 \
  /storage/apps/zitadel \
  /storage/apps/zitadel/bootstrap \
  /storage/apps/zitadel/backups

# postgres:18 монтируется в /var/lib/postgresql и повторно входит под UID 70,
# поэтому каталог данных должен оставаться проходимым (0755, а не 0700).
ensure_dirs 0755 /storage/apps/zitadel/postgresql

write_env_file "$repo_root/zitadel/.env" <<EOF
ZITADEL_HOST=id.$DOMAIN
ZITADEL_VERSION=v4.17.1
POSTGRES_DB=zitadel
POSTGRES_USER=zitadel
POSTGRES_PASSWORD=$(random_secret)
ADMIN_USERNAME=admin
ADMIN_PASSWORD=Za9!$(openssl rand -base64 18 | tr -d '=\n')
ZITADEL_MASTERKEY=$(openssl rand -hex 16)
EOF

compose_config "$repo_root/zitadel"
compose_config "$repo_root/zitadel" --profile tools
