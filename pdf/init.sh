#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p \
  "$APPS_STORAGE_PATH"/pdf/configs \
  "$APPS_STORAGE_PATH"/pdf/customFiles \
  "$APPS_STORAGE_PATH"/pdf/logs \
  "$APPS_STORAGE_PATH"/pdf/pipeline \
  "$APPS_STORAGE_PATH"/pdf/tessdata


# Конфигурация и секреты приходят через окружение: bootstrap подмешивает
# config.env и расшифровывает secrets.enc.env (sops exec-env). Plaintext .env
# не создаётся.

compose_config "$repo_root/pdf"
