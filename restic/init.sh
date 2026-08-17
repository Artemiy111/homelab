#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p \
  "$APPS_STORAGE_PATH"/restic/cache \
  "$APPS_STORAGE_PATH"/restic/restore \
  /storage/backups/restic

write_env_file "$repo_root/restic/.env" <<EOF
APPS_STORAGE_PATH=$APPS_STORAGE_PATH
RESTIC_PASSWORD=$(random_secret)
BACKUP_SOURCE=$APPS_STORAGE_PATH
CONFIG_SOURCE=$repo_root
RESTIC_REPOSITORY_PATH=/storage/backups/restic
EOF

compose_config "$repo_root/restic" --profile manual
