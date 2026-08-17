#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

write_env_file "$repo_root/mermaid-live-editor/.env" <<EOF
MERMAID_HOST=mermaid.$DOMAIN
EOF

compose_config "$repo_root/mermaid-live-editor"
