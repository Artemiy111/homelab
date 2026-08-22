#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p \
  "$APPS_STORAGE_PATH"/paperless/data \
  "$APPS_STORAGE_PATH"/paperless/media \
  "$APPS_STORAGE_PATH"/paperless/export \
  "$APPS_STORAGE_PATH"/paperless/consume \
  "$APPS_STORAGE_PATH"/paperless/postgresql \
  "$APPS_STORAGE_PATH"/paperless/redis


# Конфигурация и секреты приходят через окружение: bootstrap подмешивает
# config.env и расшифровывает secrets.env (sops exec-env). Plaintext .env
# не создаётся.

compose_config "$repo_root/paperless"
