#!/usr/bin/env bash

# Общие функции инициализации сервисов homelab.
#
# Подключение из скрипта сервиса:
#   repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
#   source "$repo_root/scripts/lib/common.sh"
#
# Скрипт задаёт $repo_root (если вызывающий ещё не задал) и определяет
# функции: random_secret, chmod_if_owned, ensure_dirs, write_env_file,
# traefik_network_cidr, compose_config.

repo_root="${repo_root:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Базовый домен homelab — единственный источник правды для имён хостов сервисов.
# Каждый сервис доступен по адресу <sub>.$DOMAIN. Приоритет значения:
#   1. переменная окружения DOMAIN;
#   2. корневой .env (не отслеживается Git, копируется из .env.example);
#   3. значение по умолчанию ниже (закоммичено).
if [[ -f "$repo_root/.env" ]]; then
  # shellcheck disable=SC1090
  source "$repo_root/.env"
fi
DOMAIN="${DOMAIN:-example.net}"

# Случайный секрет из 24 байт (hex).
random_secret() {
  openssl rand -hex 24
}

# Выставляет режим доступа каталогам, если их владелец — текущий пользователь.
# Чужие каталоги пропускаются с сообщением.
chmod_if_owned() {
  local mode="$1"
  shift
  local dir
  for dir in "$@"; do
    if [[ -O "$dir" ]]; then
      chmod "$mode" "$dir"
    else
      echo "Пропуск chmod: $dir (владелец — не текущий пользователь)"
    fi
  done
}

# Создаёт каталоги (mkdir -p) и выставляет им режим доступа через chmod_if_owned.
ensure_dirs() {
  local mode="$1"
  shift
  mkdir -p "$@"
  chmod_if_owned "$mode" "$@"
}

# Создаёт .env, если его ещё нет. Содержимое передаётся через stdin (heredoc).
# Существующий файл пропускается; новые файлы создаются с umask 077 (права 0600).
write_env_file() {
  local env_file="$1"
  if [[ -e "$env_file" ]]; then
    echo "Пропуск: $env_file уже существует"
  else
    local old_umask
    old_umask="$(umask)"
    umask 077
    cat >"$env_file"
    umask "$old_umask"
  fi
  # Гарантировать права 0600 и для уже существующих файлов.
  chmod 600 "$env_file"
}

# CIDR подсети docker-сети traefiknet (нужен некоторым сервисам в .env).
traefik_network_cidr() {
  docker network inspect traefiknet \
    --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
}

# Проверяет корректность Compose-конфигурации сервиса.
# Дополнительные аргументы (например --profile) передаются в docker compose.
compose_config() {
  local service_dir="$1"
  shift
  docker compose --project-directory "$service_dir" "$@" config --quiet
}
