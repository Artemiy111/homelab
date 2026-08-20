#!/usr/bin/env bash

# Удаляет общие переменные из .env файлов сервисов.
# Эти переменные теперь берутся из корневого .env (--env-file).
# Запуск: bash scripts/migrate-env.sh

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

GLOBAL_VARS=(DOMAIN SERVER_IP TZ DEFAULT_LOCALE APPS_STORAGE_PATH)

for env_file in "$repo_root"/*/.env; do
  [[ -f "$env_file" ]] || continue
  changed=false
  for var in "${GLOBAL_VARS[@]}"; do
    if grep -q "^${var}=" "$env_file" 2>/dev/null; then
      sed -i '' "/^${var}=/d" "$env_file"
      changed=true
    fi
  done
  if $changed; then
    echo "Очищен: ${env_file#$repo_root/}"
  fi
done

echo "Миграция завершена. Общие переменные удалены из персональных .env."
