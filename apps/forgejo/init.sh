#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p \
  "$APPS_STORAGE_PATH"/forgejo/backups \
  "$APPS_STORAGE_PATH"/forgejo/data \
  "$APPS_STORAGE_PATH"/forgejo/postgresql


# Конфигурация и секреты приходят через окружение: bootstrap подмешивает
# config.env и расшифровывает secrets.enc.env (через service_run). Plaintext .env
# не создаётся.

compose_config "$repo_root/apps/forgejo"
