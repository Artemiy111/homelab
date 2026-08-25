#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p \
  "$APPS_STORAGE_PATH"/forgejo/backups \
  "$APPS_STORAGE_PATH"/forgejo/data \
  "$APPS_STORAGE_PATH"/forgejo/postgresql

compose_config "$repo_root/apps/forgejo"
