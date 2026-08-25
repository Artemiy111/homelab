#!/usr/bin/env bash

# Общие функции инициализации сервисов homelab.
#
# Подключение из скрипта сервиса:
#   repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
#   source "$repo_root/scripts/lib/common.sh"
#
# Скрипт задаёт $repo_root (если вызывающий ещё не задал) и определяет
# функции: random_secret, random_password, chmod_if_owned, ensure_dirs,
# traefik_network_cidr, compose_config, service_env_files, service_compose,
# service_init, service_bootstrap.

repo_root="${repo_root:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Корень каталога сервисов: один подкаталог apps/<имя> на сервис.
apps_dir="${apps_dir:-$repo_root/apps}"

# Базовый домен homelab — единственный источник правды для имён хостов сервисов.
# Каждый сервис доступен по адресу <sub>.$DOMAIN. Приоритет значения:
#   1. переменная окружения DOMAIN;
#   2. корневой .env (не отслеживается Git, копируется из .env.example);
#   3. значение по умолчанию ниже (закоммичено).
if [[ -f "$repo_root/.env" ]]; then
  # shellcheck disable=SC1090
  source "$repo_root/.env"
fi

# LAN IP-адрес сервера, к которому привязываются опубликованные порты (Traefik,
# Technitium DNS, Gitea, 3x-ui, Jitsi) и на который указывают DNS/health-проверки.
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

# Рендерит файл из шаблона через vals flatten: разворачивает ref+-ссылки
# (ref+envsubst://$VAR — переменные окружения, ref+sops://… — секреты),
# сохраняя формат и комментарии шаблона. Нужные переменные должны быть
# экспортированы вызывающим скриптом. Секреты в шаблоны передаются либо
# через окружение (сервис запущен под sops exec-env), либо напрямую через
# ref+sops-ссылки на secrets.enc.env других сервисов.
render_template() {
  local template="$1" output="$2"
  vals flatten -f "$template" >"$output"
}

# Случайный секрет из 24 байт (hex).
random_secret() {
  openssl rand -hex 24
}

# Случайный пароль для входа человека, удовлетворяющий дефолтной политике
# сложности ZITADEL: >= 8 символов, upper + lower + цифра + символ.
# Алфавит URL/shell-безопасный; символ политики добавляется гарантированно,
# классы букв и цифр проверяются перегенерацией.
random_password() {
  local syms='!%*+-_=?@'
  local pw
  while :; do
    pw="$(openssl rand -base64 24 | tr -d '=\n' | tr '/+' '_-')"
    pw+="${syms:$((RANDOM % ${#syms})):1}"
    if [[ "$pw" =~ [A-Z] && "$pw" =~ [a-z] && "$pw" =~ [0-9] ]]; then
      printf '%s' "$pw"
      return
    fi
  done
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

# CIDR подсети docker-сети traefiknet (нужен некоторым сервисам в .env).
traefik_network_cidr() {
  docker network inspect traefiknet \
    --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
}

# Проверяет корректность Compose-конфигурации сервиса. Подмешивает те же
# env-файлы, что и реальный запуск (service_compose): иначе переменные из
# корневого .env (TZ, DOMAIN) не видны интерполяции и строгие проверки ${VAR:?}
# ложно падают. Дополнительные аргументы (например --profile) передаются в
# docker compose.
compose_config() {
  local service_dir="$1"
  shift
  local service
  service="$(basename "$service_dir")"
  local -a env_files=(--env-file "$repo_root/.env")
  [[ -f "$apps_dir/$service/config.env" ]] &&
    env_files+=(--env-file "$apps_dir/$service/config.env")
  docker compose --project-directory "$service_dir" \
    "${env_files[@]}" \
    "$@" config --quiet
}

# Строка --env-file для сервиса: корневой .env плюс config.env сервиса,
# если тот существует. Пути в кавычках — строка раскрывается без словоделения
# по содержимому (пути без пробелов по соглашению репо).
service_env_files() {
  local service="$1"
  local files="--env-file '$repo_root/.env'"
  [[ -f "$apps_dir/$service/config.env" ]] &&
    files+=" --env-file '$apps_dir/$service/config.env'"
  printf '%s' "$files"
}

# Запускает docker compose для сервиса. Если у сервиса есть secrets.enc.env,
# команда оборачивается в sops exec-env: расшифрованные секреты попадают
# в окружение compose в памяти процесса, plaintext-файл не создаётся.
service_compose() {
  local service="$1"
  shift
  if [[ -f "$apps_dir/$service/secrets.enc.env" ]]; then
    sops exec-env "$apps_dir/$service/secrets.enc.env" \
      "docker compose --project-directory '$apps_dir/$service' $(service_env_files "$service") $*"
  else
    docker compose \
      --project-directory "$apps_dir/$service" \
      $(service_env_files "$service") \
      "$@"
  fi
}

# Выполняет init.sh сервиса (каталоги данных, шаблоны, валидация конфигурации).
# config.env подмешивается в окружение, секреты — через sops exec-env.
service_init() {
  local service="$1"
  local init_cmd="bash '$apps_dir/$service/init.sh'"
  [[ -f "$apps_dir/$service/config.env" ]] &&
    init_cmd="set -a && . '$apps_dir/$service/config.env' && $init_cmd"
  if [[ -f "$apps_dir/$service/secrets.enc.env" ]]; then
    sops exec-env "$apps_dir/$service/secrets.enc.env" "$init_cmd"
  else
    bash "$apps_dir/$service/init.sh"
  fi
}

# Полный цикл одного сервиса: init.sh + compose up -d.
service_bootstrap() {
  local service="$1"
  service_init "$service"
  service_compose "$service" up -d --remove-orphans
}
