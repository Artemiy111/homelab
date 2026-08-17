#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

write_env_file "$repo_root/structurizr/.env" <<EOF
STRUCTURIZR_HOST=structurizr.$DOMAIN
EOF

render_domain_template "$repo_root/structurizr/structurizr.properties.tpl" "$repo_root/structurizr/structurizr.properties"

compose_config "$repo_root/structurizr"
