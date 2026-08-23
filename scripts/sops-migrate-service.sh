#!/usr/bin/env bash

# Миграция одного сервиса с самописной генерации .env на SOPS + age.
# Запускается НА СЕРВЕРЕ от имени artlab (нужен приватный age-ключ):
#   bash scripts/sops-migrate-service.sh traefik TRAEFIK_DASHBOARD_PASSWORD,TRAEFIK_DASHBOARD_USERS,RFC2136_TSIG_SECRET
#
# Второй аргумент — ЯВНЫЙ список секретных ключей (классификация выполняет
# человек по init.sh и compose.yaml сервиса, список фиксируется в коммите).
# Скрипт раскладывает существующий <service>/.env на два файла:
#   <service>/config.env  — публичная конфигурация (plaintext, tracked);
#   <service>/secrets.enc.env — только секреты, зашифрован SOPS+age целиком.
# Глобальные переменные (DOMAIN, SERVER_IP, TZ, APPS_STORAGE_PATH) в
# config.env не переносятся — они уже есть в корневом .env.

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Использование: $0 <каталог-сервиса> <СЕКРЕТНЫЙ_КЛЮЧ1,КЛЮЧ2,...>" >&2
  exit 1
fi

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

service="$1"
service_dir="$repo_root/$service"
env_file="$service_dir/.env"
config_file="$service_dir/config.env"
encrypted="$service_dir/secrets.enc.env"
age_key_file="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

# Глобальные переменные остаются в корневом .env, в config.env им не место.
globals_re='^(DOMAIN|DEFAULT_LOCALE|SERVER_IP|TZ|APPS_STORAGE_PATH)='

if [[ ! -d "$service_dir" ]]; then
  echo "Ошибка: каталог $service_dir не найден" >&2
  exit 1
fi
if [[ ! -f "$env_file" ]]; then
  echo "Ошибка: $env_file не существует — мигрировать нечего" >&2
  exit 1
fi
if [[ -f "$encrypted" || -f "$config_file" ]]; then
  echo "Ошибка: secrets.enc.env или config.env уже существуют — сервис уже мигрирован" >&2
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

# Разбор списка секретных ключей.
declare -A secret_keys=()
IFS=',' read -r -a key_list <<<"$2"
for key in "${key_list[@]}"; do
  key="$(printf '%s' "$key" | tr -d '[:space:]')"
  [[ -n "$key" ]] || continue
  secret_keys["$key"]=1
done
if [[ ${#secret_keys[@]} -eq 0 ]]; then
  echo "Ошибка: пустой список секретных ключей" >&2
  exit 1
fi

# Раскладываем строки .env: секретные — во временный файл для шифрования,
# остальные (плюс комментарии) — в config.env.
tmp_plaintext="$(mktemp /tmp/sops-migrate-XXXXXX-secrets.enc.env)"
trap 'rm -f "$tmp_plaintext"' EXIT

secret_names=()
config_count=0
while IFS= read -r line || [[ -n "$line" ]]; do
  case "$line" in
    '#'*|'') printf '%s\n' "$line" >>"$config_file"; continue ;;
  esac
  key="${line%%=*}"
  value="${line#*=}"
  # Нормализуем кавычи значений: парсер dotenv в Compose их снимает,
  # а sops сохранил бы как часть значения (ломает, например, htpasswd).
  case "$value" in
    "'"*"'") value="${value#\'}"; value="${value%\'}" ;;
    '"'*) value="${value#\"}"; value="${value%\"}" ;;
  esac
  line="${key}=${value}"
  if [[ -n "${secret_keys[$key]:-}" ]]; then
    printf '%s\n' "$line" >>"$tmp_plaintext"
    secret_names+=("$key")
  else
    if [[ "$line" =~ $globals_re ]]; then
      echo "Пропущен глобальный ключ: ${key}" >&2
    else
      printf '%s\n' "$line" >>"$config_file"
      config_count=$((config_count + 1))
    fi
  fi
done <"$env_file"

# Проверяем, что все заявленные секреты найдены в .env.
missing=()
for key in "${!secret_keys[@]}"; do
  grep -q "^${key}=" "$env_file" || missing+=("$key")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Ошибка: ключи не найдены в $env_file: ${missing[*]}" >&2
  rm -f "$config_file"
  exit 1
fi

umask 077
sops --encrypt "$tmp_plaintext" >"$encrypted"
chmod 600 "$encrypted"

echo "Создан: $config_file ($config_count переменных конфигурации)"
echo "Создан: $encrypted (секреты: ${secret_names[*]})"
echo "Дальнейшие шаги:"
echo "  1. Перенести оба файла в локальную рабочую копию на macOS"
echo "     (secrets.enc.env зашифрован, его содержимое можно выводить в логи;"
echo "     config.env не содержит секретов)."
echo "  2. Закоммитить с указанием классификации, push, git pull --ff-only."
echo "  3. Проверить: bash scripts/compose-secrets.sh $service config --quiet."
echo "  4. После успеха удалить старый plaintext: rm $env_file."
