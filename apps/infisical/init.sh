#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

# postgres:14 монтируется в /var/lib/postgresql и повторно входит под UID 70,
# а redis:7 под UID 999, поэтому каталоги данных должны оставаться проходимыми
# (0755, а не 0700).
ensure_dirs 0755 \
  "$APPS_STORAGE_PATH"/infisical \
  "$APPS_STORAGE_PATH"/infisical/postgresql \
  "$APPS_STORAGE_PATH"/infisical/redis

# Конфигурация и секреты приходят через окружение: bootstrap подмешивает
# config.env и расшифровывает secrets.enc.env (через service_run). Plaintext .env
# не создаётся.

compose_config "$repo_root/apps/infisical"
