#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p \
  /storage/apps/restic/cache \
  /storage/apps/restic/restore \
  /storage/backups/restic

write_env_file "$repo_root/restic/.env" <<EOF
RESTIC_PASSWORD=$(random_secret)
BACKUP_SOURCE=/storage/apps
CONFIG_SOURCE=$repo_root
RESTIC_REPOSITORY_PATH=/storage/backups/restic
EOF

compose_config "$repo_root/restic" --profile manual
