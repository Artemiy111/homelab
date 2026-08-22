#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 \
  "$APPS_STORAGE_PATH"/zitadel \
  "$APPS_STORAGE_PATH"/zitadel/bootstrap \
  "$APPS_STORAGE_PATH"/zitadel/backups

# postgres:18 монтируется в /var/lib/postgresql и повторно входит под UID 70,
# поэтому каталог данных должен оставаться проходимым (0755, а не 0700).
ensure_dirs 0755 "$APPS_STORAGE_PATH"/zitadel/postgresql

# Masterkey хранится отдельным файлом (0600): ZITADEL v4 не читает его из
# переменной окружения, только --masterkey / --masterkeyFile. Существующий файл
# не перезаписывать — ключом зашифрованы данные базы.
if [ ! -e "$APPS_STORAGE_PATH"/zitadel/masterkey ]; then
  umask 077
  printf '%s' "$(openssl rand -hex 16)" > "$APPS_STORAGE_PATH"/zitadel/masterkey
fi

compose_config "$repo_root/zitadel"
compose_config "$repo_root/zitadel" --profile tools
