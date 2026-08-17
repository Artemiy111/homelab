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
export DOMAIN

# LAN IP-адрес сервера, к которому привязываются опубликованные порты (Traefik,
# Pi-hole, Gitea, 3x-ui, Jitsi) и на который указывают DNS/health-проверки.
# Приоритет: переменная окружения SERVER_IP → корневой .env → автоопределение.
detect_server_ip() {
  local ip
  ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }')"
  if [[ -n "$ip" ]]; then
    printf '%s\n' "$ip"
    return 0
  fi
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  if [[ -n "$ip" ]]; then
    printf '%s\n' "$ip"
    return 0
  fi
  return 1
}
SERVER_IP="${SERVER_IP:-$(detect_server_ip || true)}"
export SERVER_IP
if [[ -z "$SERVER_IP" ]]; then
  echo "Внимание: не удалось определить IP-адрес сервера; задайте SERVER_IP в корневом .env." >&2
fi

# Часовой пояс контейнеров — единый источник правды (как DOMAIN/SERVER_IP).
# Приоритет: переменная окружения TZ → корневой .env → значение ниже.
TZ="${TZ:-Asia/Yekaterinburg}"

# Генерирует файл из шаблона, подставляя перечисленные переменные в стандартном
# синтаксисе ${VAR} (тот же, что и в Compose) через envsubst. Подставляются только
# указанные имена, поэтому чужие ${...} остаются нетронутыми. DOMAIN и SERVER_IP
# экспортируются из common.sh; прочие переменные (например LETSENCRYPT_EMAIL)
# экспортирует вызывающий скрипт. По умолчанию подставляется только ${DOMAIN}.
render_template() {
  local template="$1" output="$2" vars="${3:-\$DOMAIN}"
  envsubst "$vars" < "$template" > "$output"
}

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
