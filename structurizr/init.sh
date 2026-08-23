#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

render_template "$repo_root/structurizr/structurizr.tpl.properties" "$repo_root/structurizr/structurizr.properties"

compose_config "$repo_root/structurizr"
