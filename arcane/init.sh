#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 \
  "$APPS_STORAGE_PATH"/arcane \
  "$APPS_STORAGE_PATH"/arcane/data

write_env_file "$repo_root/arcane/.env" <<EOF
ARCANE_HOST=arcane.$DOMAIN
ENCRYPTION_KEY=$(openssl rand -hex 32)
JWT_SECRET=$(openssl rand -hex 32)
EOF

compose_config "$repo_root/arcane"
