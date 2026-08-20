#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 "$APPS_STORAGE_PATH/vault/data"

write_env_file "$repo_root/vault/.env" <<EOF
VAULT_HOST=vault.$DOMAIN
VAULT_VERSION=2.0.3
EOF

compose_config "$repo_root/vault"
