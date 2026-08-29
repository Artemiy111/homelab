#!/usr/bin/env bash

# Общие функции инициализации сервисов homelab.
#
# Подключение из скрипта сервиса:
#   repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
#   source "$repo_root/scripts/lib/common.sh"
#
# Скрипт задаёт $repo_root (если вызывающий ещё не задал) и определяет
# функции: random_secret, random_password, chmod_if_owned, ensure_dirs,
# traefik_network_cidr, compose_config, service_env_files, service_secret_args,
# service_run, service_compose, service_init, service_bootstrap.

repo_root="${repo_root:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Корень каталога сервисов: один подкаталог apps/<имя> на сервис.
apps_dir="${apps_dir:-$repo_root/apps}"

# Базовый домен homelab — единственный источник правды для имён хостов сервисов.
# Каждый сервис доступен по адресу <sub>.$DOMAIN. Приоритет значения:
#   1. переменная окружения DOMAIN;
#   2. корневой config.env (не отслеживается Git, копируется из config.example.env);
#   3. значение по умолчанию ниже (закоммичено).
if [[ -f "$repo_root/config.env" ]]; then
  # shellcheck disable=SC1090
  source "$repo_root/config.env"
fi

# LAN IP-адрес сервера, к которому привязываются опубликованные порты (Traefik,
# Technitium DNS, Gitea, 3x-ui, Jitsi) и на который указывают DNS/health-проверки.
# Приоритет: переменная окружения SERVER_IP → корневой config.env → автоопределение.
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
  echo "Внимание: не удалось определить IP-адрес сервера; задайте SERVER_IP в корневом config.env." >&2
fi

# Рендерит файл из шаблона через vals flatten: разворачивает ref+-ссылки
# (ref+envsubst://$VAR — переменные окружения, ref+sops://… — секреты),
# сохраняя формат и комментарии шаблона. Нужные переменные должны быть
# экспортированы вызывающим скриптом. Секреты в шаблоны передаются либо
# через окружение (сервис запущен под service_run), либо напрямую через
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

# CIDR подсети docker-сети traefiknet (нужен некоторым сервисам в их config.env).
traefik_network_cidr() {
  docker network inspect traefiknet \
    --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
}

# Проверяет корректность Compose-конфигурации сервиса. Подмешивает те же
# env-файлы, что и реальный запуск (service_compose): иначе переменные из
# корневого config.env (TZ, DOMAIN) не видны интерполяции и строгие проверки ${VAR:?}
# ложно падают. Дополнительные аргументы (например --profile) передаются в
# docker compose.
compose_config() {
  local service_dir="$1"
  shift
  local service
  service="$(basename "$service_dir")"
  local -a args=(docker compose --project-directory "$service_dir")
  local f
  while IFS= read -r f; do args+=(--env-file "$f"); done < <(service_env_files "$service")
  service_run "$service" "${args[@]}" "$@" config --quiet
}

# Список env-файлов сервиса (по одному на строку): корневой config.env
# и config.env сервиса, если существует.
service_env_files() {
  local service="$1"
  [[ -f "$repo_root/config.env" ]] && printf '%s\n' "$repo_root/config.env"
  [[ -f "$apps_dir/$service/config.env" ]] && printf '%s\n' "$apps_dir/$service/config.env"
}

# Печатает расшифрованные секреты сервиса построчно в виде K=V — для передачи
# одним элементом argv в env(1). Значения не интерполируются и не экранируются;
# формат secrets.enc.env — плоский dotenv без переводов строк внутри значений.
# У сервиса без secrets.enc.env вывод пуст — это норма (секретов нет).
service_secret_args() {
  local service="$1"
  local enc="$apps_dir/$service/secrets.enc.env"
  [[ -f "$enc" ]] || return 0
  local line
  while IFS= read -r line; do
    [[ "$line" == *=* && "$line" != "#"* ]] && printf '%s\n' "$line"
  done < <(sops -d "$enc")
}

# Выполняет команду в окружении секретов сервиса, если они есть: значения
# попадают в environ потомка дословно через env(1), приоритет выше любых
# --env-file. У сервиса без secrets.enc.env секретных аргументов нет — env
# просто выполняет команду.
service_run() {
  local service="$1"
  shift
  local -a secargs=() line
  while IFS= read -r line; do secargs+=("$line"); done < <(service_secret_args "$service")
  env "${secargs[@]}" "$@"
}

# Запускает docker compose для сервиса. Окружение интерполяции: корневой
# .env → config.env (--env-file), поверх них — секреты из окружения процесса.
service_compose() {
  local service="$1"
  shift
  local -a args=(docker compose --project-directory "$apps_dir/$service")
  local f
  while IFS= read -r f; do args+=(--env-file "$f"); done < <(service_env_files "$service")
  service_run "$service" "${args[@]}" "$@"
}

# Выполняет init.sh сервиса (каталоги данных, шаблоны, валидация конфигурации):
# config.env экспортируется в окружение, секреты добавляет service_run.
service_init() {
  local service="$1"
  local dir="$apps_dir/$service"
  if [[ -f "$dir/config.env" ]]; then
    service_run "$service" \
      bash -c 'set -a; . "$1"; set +a; exec bash "$2"' _ "$dir/config.env" "$dir/init.sh"
  else
    service_run "$service" bash "$dir/init.sh"
  fi
}

# Полный цикл одного сервиса: init.sh (до up) + compose up -d + опциональный
# init-postinstall.sh (после up, если требует запущенный контейнер).
service_bootstrap() {
  local service="$1"
  service_init "$service"
  service_compose "$service" up -d --remove-orphans
  local post="$apps_dir/$service/init-postinstall.sh"
  if [[ -f "$post" ]]; then
    service_run "$service" bash "$post"
  fi
}
