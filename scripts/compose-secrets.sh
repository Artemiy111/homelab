#!/usr/bin/env bash

# Запуск Compose-команд сервиса в окружении его расшифрованных секретов:
#   bash scripts/compose-secrets.sh traefik config --quiet
#   bash scripts/compose-secrets.sh traefik up -d
#
# Расшифровывает <сервис>/secrets.env через `sops exec-env` и передаёт
# переменные в docker compose как переменные окружения — plaintext-файл
# не создаётся. Требует приватный age-ключ, поэтому работает только на
# сервере (от имени artlab). Корневой .env подмешивается через --env-file,
# значения из secrets.env имеют приоритет.

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Использование: $0 <каталог-сервиса> <аргументы compose...>" >&2
  exit 1
fi

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
service="$1"
shift

encrypted="$repo_root/$service/secrets.env"
if [[ ! -f "$encrypted" ]]; then
  echo "Ошибка: $encrypted не найден — сервис не мигрирован на SOPS" >&2
  exit 1
fi

# sops exec-env принимает команду одним аргументом и запускает её через
# /bin/sh -c, поэтому compose-вызов склеивается в одну строку. Пути внутри
# репозитория не содержат пробелов. Приоритет: корневой .env → config.env
# сервиса → расшифрованные секреты (окружение, высший).
env_files=(--env-file "$repo_root/.env")
if [[ -f "$repo_root/$service/config.env" ]]; then
  env_files+=(--env-file "$repo_root/$service/config.env")
fi

exec sops exec-env "$encrypted" \
  "docker compose --project-directory '$repo_root/$service' ${env_files[*]} $*"
