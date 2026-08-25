#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p \
  "$APPS_STORAGE_PATH"/pdf/configs \
  "$APPS_STORAGE_PATH"/pdf/customFiles \
  "$APPS_STORAGE_PATH"/pdf/logs \
  "$APPS_STORAGE_PATH"/pdf/pipeline \
  "$APPS_STORAGE_PATH"/pdf/tessdata

compose_config "$repo_root/apps/pdf"
