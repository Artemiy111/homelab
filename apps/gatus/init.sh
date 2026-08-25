#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0750 \
  "$APPS_STORAGE_PATH"/gatus \
  "$APPS_STORAGE_PATH"/gatus/data

compose_config "$repo_root/apps/gatus"
