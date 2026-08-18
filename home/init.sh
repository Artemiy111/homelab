#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

write_env_file "$repo_root/home/.env" <<EOF
HOMEPAGE_HOST=home.$DOMAIN
DOMAIN=$DOMAIN
EOF

render_template "$repo_root/home/config/settings.yaml.tpl" \
  "$repo_root/home/config/settings.yaml" '\$DEFAULT_LOCALE'

compose_config "$repo_root/home"
