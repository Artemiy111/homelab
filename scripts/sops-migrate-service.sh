#!/usr/bin/env bash

# Миграция одного сервиса с самописной генерации .env на SOPS + age.
# Запускается НА СЕРВЕРЕ от имени artlab (нужен приватный age-ключ):
#   bash scripts/sops-migrate-service.sh traefik
#
# Скрипт шифрует существующий <service>/.env в <service>/secrets.env
# (dotenv-формат SOPS). Получившийся зашифрованный файл переносится в
# рабочую копию на macOS (вывести через cat и записать локально), там
# коммитится и доставляется на сервер по стандартной схеме push/pull.
# С этого момента сервис запускается через sops exec-env (см.
# scripts/compose-secrets.sh и bootstrap-platform.sh), plaintext .env
# не создаётся.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Использование: $0 <каталог-сервиса>" >&2
  exit 1
fi

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

service_dir="$repo_root/$1"
env_file="$service_dir/.env"
encrypted="$service_dir/secrets.env"
age_key_file="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

if [[ ! -d "$service_dir" ]]; then
  echo "Ошибка: каталог $service_dir не найден" >&2
  exit 1
fi
if [[ ! -f "$env_file" ]]; then
  echo "Ошибка: $env_file не существует — мигрировать нечего" >&2
  exit 1
fi
if [[ -f "$encrypted" ]]; then
  echo "Ошибка: $encrypted уже существует — сервис уже мигрирован" >&2
  exit 1
fi
if ! command -v sops >/dev/null 2>&1; then
  echo "Ошибка: sops не установлен (см. ansible/host.yml)" >&2
  exit 1
fi
if [[ ! -f "$age_key_file" ]]; then
  echo "Ошибка: нет приватного age-ключа: $age_key_file" >&2
  exit 1
fi

umask 077
sops --encrypt "$env_file" >"$encrypted"
chmod 600 "$encrypted"

echo "Создан: $encrypted"
echo "Дальнейшие шаги:"
echo "  1. Перенести содержимое $encrypted в локальную рабочую копию на macOS"
echo "     (например: ssh homelab-agent 'cat .../secrets.env' > secrets.env)."
echo "     Файл зашифрован, его содержимое можно выводить в логи."
echo "  2. Закоммитить, выполнить push, затем на сервере git pull --ff-only."
echo "  3. Проверить запуск сервиса: bash scripts/compose-secrets.sh $1 config."
