#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 "$APPS_STORAGE_PATH/local-ai/models"

write_env_file "$repo_root/local-ai/.env" <<EOF
LOCALAI_HOST=localai.$DOMAIN
LOCALAI_API_KEY=$(random_secret)
EOF

compose_config "$repo_root/local-ai"
