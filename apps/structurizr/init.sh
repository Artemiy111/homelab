#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

render_template "$repo_root/apps/structurizr/structurizr.tpl.properties" "$repo_root/apps/structurizr/structurizr.properties"

compose_config "$repo_root/apps/structurizr"
