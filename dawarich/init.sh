#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p \
  "$APPS_STORAGE_PATH"/dawarich/backups \
  "$APPS_STORAGE_PATH"/dawarich/postgresql \
  "$APPS_STORAGE_PATH"/dawarich/public \
  "$APPS_STORAGE_PATH"/dawarich/redis \
  "$APPS_STORAGE_PATH"/dawarich/shared \
  "$APPS_STORAGE_PATH"/dawarich/storage \
  "$APPS_STORAGE_PATH"/dawarich/watched

# Конфигурация и секреты приходят через окружение: bootstrap подмешивает
# config.env и расшифровывает secrets.enc.env (sops exec-env). Plaintext .env
# не создаётся.

compose_config "$repo_root/dawarich"
