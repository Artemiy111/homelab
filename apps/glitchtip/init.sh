#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

# postgres:18-alpine монтируется в /var/lib/postgresql (PGDATA внутри —
# /var/lib/postgresql/18/docker) и повторно входит под UID 70, а valkey:9
# под UID 999, поэтому каталоги данных должны оставаться проходимыми
# (0755, а не 0700).
ensure_dirs 0755 \
  "$APPS_STORAGE_PATH"/glitchtip \
  "$APPS_STORAGE_PATH"/glitchtip/postgresql \
  "$APPS_STORAGE_PATH"/glitchtip/valkey

# Конфигурация и секреты приходят через окружение: bootstrap подмешивает
# config.env и расшифровывает secrets.enc.env (sops exec-env). Plaintext .env
# не создаётся.

compose_config "$repo_root/apps/glitchtip"
