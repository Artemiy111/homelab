#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p \
  "$APPS_STORAGE_PATH"/nextcloud/backups \
  "$APPS_STORAGE_PATH"/nextcloud/html \
  "$APPS_STORAGE_PATH"/nextcloud/postgresql \
  "$APPS_STORAGE_PATH"/nextcloud/redis


# Конфигурация и секреты приходят через окружение: bootstrap подмешивает
# config.env и расшифровывает secrets.env (sops exec-env). Plaintext .env
# не создаётся.

compose_config "$repo_root/nextcloud"
