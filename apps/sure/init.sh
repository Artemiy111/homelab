#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 \
  "$APPS_STORAGE_PATH/sure/data/app" \
  "$APPS_STORAGE_PATH/sure/data/postgresql" \
  "$APPS_STORAGE_PATH/sure/data/redis" \
  "$APPS_STORAGE_PATH/sure/data/backups"

compose_config "$repo_root/apps/sure"
