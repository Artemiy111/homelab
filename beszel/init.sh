#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p \
  /storage/apps/beszel/data \
  /storage/apps/beszel/agent \
  /storage/apps/beszel/socket

write_env_file "$repo_root/beszel/.env" <<EOF
BESZEL_HOST=beszel.$DOMAIN
BESZEL_AGENT_KEY=
BESZEL_AGENT_TOKEN=
EOF

compose_config "$repo_root/beszel" --profile agent
