#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0750 \
  /storage/apps/code-server \
  /storage/apps/code-server/home \
  /storage/apps/code-server/workspace

write_env_file "$repo_root/code-server/.env" <<EOF
CODE_SERVER_HOST=code.$DOMAIN
CODE_SERVER_UID=$(id -u)
CODE_SERVER_GID=$(id -g)
CODE_SERVER_USER=${USER:-artlab}
EOF

compose_config "$repo_root/code-server"
