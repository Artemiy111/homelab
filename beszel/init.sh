#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p \
  "$APPS_STORAGE_PATH"/beszel/data \
  "$APPS_STORAGE_PATH"/beszel/agent \
  "$APPS_STORAGE_PATH"/beszel/socket

write_env_file "$repo_root/beszel/.env" <<EOF
APPS_STORAGE_PATH=$APPS_STORAGE_PATH
BESZEL_HOST=beszel.$DOMAIN
BESZEL_AGENT_KEY=
BESZEL_AGENT_TOKEN=
EOF

compose_config "$repo_root/beszel" --profile agent
