#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 \
  "$APPS_STORAGE_PATH"/3x-ui \
  "$APPS_STORAGE_PATH"/3x-ui/db \
  "$APPS_STORAGE_PATH"/3x-ui/log

compose_config "$repo_root/apps/3x-ui"
