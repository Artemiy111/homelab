#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 \
  "$APPS_STORAGE_PATH"/authentik \
  "$APPS_STORAGE_PATH"/authentik/backups \
  "$APPS_STORAGE_PATH"/authentik/data \
  "$APPS_STORAGE_PATH"/authentik/postgresql

compose_config "$repo_root/apps/authentik"
