#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0750 \
  "$APPS_STORAGE_PATH"/technitium/etc \
  "$APPS_STORAGE_PATH"/technitium/data

compose_config "$repo_root/apps/technitium"
