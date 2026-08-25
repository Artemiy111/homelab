#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

render_template "$repo_root/home/config/settings.tpl.yaml" \
  "$repo_root/home/config/settings.yaml"

compose_config "$repo_root/home"
