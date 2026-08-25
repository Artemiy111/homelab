#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 \
  "$APPS_STORAGE_PATH"/rustfs \
  "$APPS_STORAGE_PATH"/rustfs/data

# Конфигурация и секреты приходят через окружение: bootstrap подмешивает
# config.env и расшифровывает secrets.enc.env (sops exec-env). Plaintext .env
# не создаётся.

compose_config "$repo_root/rustfs"
