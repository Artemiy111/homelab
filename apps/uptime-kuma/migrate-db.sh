#!/usr/bin/env bash
#
# Перенос данных Uptime Kuma из встроенной MariaDB в отдельный кластер
# uptime-kuma-mariadb под mariadb-operator.
#
# Встроенный инстанс (embedded-mariadb) доступен только внутри пода Kuma и только
# через unix-сокет, поэтому дамп снимается оттуда. Аутентификация в нём — по
# сокету, пароль не нужен и нигде не светится. Внешний кластер наоборот требует
# пароль root, и скрипт берёт его из Secret uptime-kuma-mariadb-root, который
# Vso кладёт из Vault: значение не попадает ни в аргументы командной строки
# хостовой стороны, ни в этот файл.
#
# Скрипт НЕ переключает Kuma на новую базу (это отдельная правка Deployment с
# UPTIME_KUMA_DB_TYPE) и НЕ удаляет старые данные. Оба шага — осознанно ручные,
# чтобы между ними можно было проверить результат.
#
# Запускать на сервере из корня репозитория, после того как применены
# манифесты кластера и синхронизированы секреты:
#
#   kubectl apply -f platform/mariadb/uptime-kuma-mariadb.instance.yaml
#   kubectl apply -f platform/mariadb/uptime-kuma-mariadb.databases.yaml
#   kubectl apply -f platform/mariadb/uptime-kuma-mariadb.users.yaml
#   kubectl apply -f apps/uptime-kuma/k8s/vaultstaticsecret-mariadb.yaml
#   apps/uptime-kuma/migrate-db.sh
#
# Повторный запуск безопасен: база-цель очищается перед заливкой.

set -euo pipefail

NAMESPACE="uptime-kuma"
MARIADB="uptime-kuma-mariadb"
ROOT_SECRET="uptime-kuma-mariadb-root"
ROOT_SECRET_KEY="INIT_UPTIME_KUMA_MARIADB_ROOT_PASSWORD"
LOADER_POD="uptime-kuma-db-load"
MARIADB_IMAGE="mariadb:13.0@sha256:d4fdec0510ad498e4f3127da30a99df3745bd6d5e611ae6ac5f76403d9284a8d"
DUMP="${TMPDIR:-/tmp}/uptime-kuma-dump-$$.sql"

info() { printf '\033[1;36m%s\033[0m\n' "$*" >&2; }
ok()   { printf '\033[1;32m%s\033[0m\n' "$*" >&2; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mОшибка: %s\033[0m\n' "$*" >&2; exit 1; }

kubectl_cmd() { kubectl -n "$NAMESPACE" "$@"; }

# SQL на stdin, вывод без заголовков. Пароль раскрывается внутри контейнера.
# Работает только после создания под-подгрузчика.
mariadb_query() {
  kubectl_cmd exec -i "$LOADER_POD" -- sh -c \
    "mariadb -h '$MARIADB' -u root -p\"\$MARIADB_ROOT_PASSWORD\" -N -B '$db'"
}

cleanup() {
  kubectl_cmd delete pod "$LOADER_POD" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  rm -f "$DUMP"
}
trap cleanup EXIT

# --- Предусловия -----------------------------------------------------------
info 'Проверяю, что кластер на месте'

kubectl_cmd get mariadb "$MARIADB" >/dev/null 2>&1 \
  || die "нет CR $MARIADB. Примени platform/mariadb/uptime-kuma-mariadb.instance.yaml."

kubectl_cmd get database uptime-kuma >/dev/null 2>&1 \
  || die 'нет CR Database uptime-kuma. Примени platform/mariadb/uptime-kuma-mariadb.databases.yaml.'

kubectl_cmd get secret "$ROOT_SECRET" >/dev/null 2>&1 \
  || die "нет Secret $ROOT_SECRET. Создай kv/uptime-kuma/root в Vault и дождись синхронизации Vso."

ready="$(kubectl_cmd get mariadb "$MARIADB" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
[[ "$ready" == "True" ]] || die "кластер $MARIADB не готов (Ready=$ready). Посмотри kubectl -n $NAMESPACE get pods,pvc."

# Имя базы берём у самой Kuma, чтобы дамп лёг в ту же базу, что была.
db="$(kubectl_cmd exec deploy/uptime-kuma -- \
        node -p 'require("/app/data/db-config.json").dbName' 2>/dev/null | tr -d '\r\n')"
[[ -n "$db" ]] || die 'не удалось прочитать dbName из /app/data/db-config.json.'
info "База источника: $db (${db} на стороне внешнего кластера задана манифестом)"

[[ "$db" == "kuma" ]] \
  || die "имя базы в db-config.json ($db) разошлось с манифестом (kuma). Проверь databases.yaml."

# --- Счётчики до переноса --------------------------------------------------
count_query="SELECT CONCAT(TABLE_NAME, '=', TABLE_ROWS) FROM information_schema.TABLES \
WHERE TABLE_SCHEMA = '$db' AND TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME;"

source_counts="$(kubectl_cmd exec deploy/uptime-kuma -- \
  mariadb --socket=/app/data/run/mariadb.sock -u node -N -B -e "$count_query" 2>/dev/null | tr -d '\r')"
[[ -n "$source_counts" ]] || die 'не удалось снять счётчики со встроенной базы.'
info "Источник: $(wc -l <<<"$source_counts" | tr -d ' ') таблиц"

# --- Дамп ------------------------------------------------------------------
# --single-transaction: согласованный снимок InnoDB без остановки Kuma.
# Плата — в целевую базу не попадут heartbeat'ы за последние секунды до конца
# дампа; для мониторинга это несущественно, а повторный прогон их довыгрузит.
info 'Снимаю дамп со встроенной MariaDB (Kuma продолжает работать)'

kubectl_cmd exec deploy/uptime-kuma -- \
  mariadb-dump --socket=/app/data/run/mariadb.sock -u node \
  --single-transaction --hex-blob --default-character-set=utf8mb4 "$db" \
  >"$DUMP"

[[ -s "$DUMP" ]] || die 'дамп пустой.'
dump_size="$(du -h "$DUMP" | cut -f1)"
info "Дамп: $DUMP ($dump_size)"

# --- Подгрузчик ------------------------------------------------------------
# Временный под только чтобы иметь mysql-клиент и пароль из Secret: пароль
# подставляется переменной окружения, поэтому в манифесте и в argv на хосте его
# нет. Удаляется в trap.
info 'Поднимаю временный под-подгрузчик'

loader_manifest="$(mktemp)"
cat >"$loader_manifest" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $LOADER_POD
  namespace: $NAMESPACE
spec:
  restartPolicy: Never
  securityContext:
    runAsUser: 999
    runAsGroup: 999
    runAsNonRoot: true
    allowPrivilegeEscalation: false
    capabilities:
      drop: ["ALL"]
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: loader
      image: "$MARIADB_IMAGE"
      command: ["sleep", "3600"]
      env:
        - name: MARIADB_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: $ROOT_SECRET
              key: $ROOT_SECRET_KEY
EOF
kubectl apply -f "$loader_manifest" >/dev/null
rm -f "$loader_manifest"

kubectl_cmd wait --for=condition=Ready "pod/$LOADER_POD" --timeout=180s >/dev/null

# --- Заливка ---------------------------------------------------------------
# Целевая база очищается: повторный запуск не должен ловить ошибку «таблица уже
# есть». Пользователь kuma в кластере остаётся: он создан оператором отдельным
# CR, а DROP DATABASE базы не делает.
#
# Клиент всегда запускается через `sh -c` с переменной окружения: пароль должен
# раскрыться внутри контейнера, иначе он попадёт в argv на хосте. Сам SQL
# передаётся на stdin, чтобы не вызывать проблем с кавычками.
info 'Заливаю дамп во внешний кластер'

kubectl_cmd exec -i "$LOADER_POD" -- sh -c \
  "mariadb -h '$MARIADB' -u root -p\"\$MARIADB_ROOT_PASSWORD\" -e 'DROP DATABASE IF EXISTS $db; CREATE DATABASE $db CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;'"

kubectl_cmd exec -i "$LOADER_POD" -- sh -c \
  "mariadb -h '$MARIADB' -u root -p\"\$MARIADB_ROOT_PASSWORD\" '$db'" <"$DUMP"

# --- Проверка --------------------------------------------------------------
info 'Сверяю счётчики'

target_counts="$(printf '%s' "$count_query" | mariadb_query)"
[[ -n "$target_counts" ]] || die 'не удалось снять счётчики с целевой базы.'

# TABLE_ROWS у InnoDB — оценка, а не точное число, поэтому сравниваем по
# наличию таблиц: расхождение означало бы, что дамп залился не полностью.
src_tables="$(cut -d= -f1 <<<"$source_counts" | sort | tr '\n' ' ')"
dst_tables="$(cut -d= -f1 <<<"$target_counts" | sort | tr '\n' ' ')"
if [[ "$src_tables" != "$dst_tables" ]]; then
  warn 'Наборы таблиц разошлись:'
  diff <(cut -d= -f1 <<<"$source_counts" | sort) <(cut -d= -f1 <<<"$target_counts" | sort) >&2 || true
  die 'миграция неполная, база-цель не трогай до разбора.'
fi
ok "Все таблицы на месте: $(wc -l <<<"$dst_tables" | tr -d ' ')"

# Сколько данных реально залилось — полезно для оценки следующего расширения тома.
size_mb="$(printf '%s' "SELECT ROUND(SUM(data_length+index_length)/1048576,1) FROM information_schema.tables WHERE table_schema='$db';" \
  | mariadb_query | tr -d '\r')"
info "Полезные данные в целевой базе: ${size_mb:-?} МБ"

# --- Дальше ----------------------------------------------------------------
ok 'Данные перенесены.'
cat >&2 <<EOF

Дальше, по шагам:

1. Переключить Kuma на внешнюю базу: добавить в Deployment переменные
   UPTIME_KUMA_DB_TYPE=mariadb, UPTIME_KUMA_DB_HOSTNAME=$MARIADB,
   UPTIME_KUMA_DB_PORT=3306, UPTIME_KUMA_DB_NAME=$db, а также
   UPTIME_KUMA_DB_USERNAME и UPTIME_KUMA_DB_PASSWORD из Secret
   $MARIADB. Переменные перекрывают db-config.json (server/setup-database.js,
   приоритет env над файлом), поэтому Kuma сама перепишет конфиг.

2. kubectl apply -k apps/uptime-kuma/ и проверить, что в UI видны все мониторы
   и status page, а /metrics отдаётся.

3. Только после этого удалить старые данные из тома uptime-kuma-data:
   каталоги /app/data/mariadb и /app/data/run. Сам PVC не удаляется: в нём
   остаются upload/, screenshots/ и error.log.

Учти: Kuma 2.x всегда записывает параметры подключения в /app/data/db-config.json
вместе с паролем, независимо от способа подачи (UPTIME_KUMA_DB_PASSWORD или
_FILE). Это её устройство, а не ошибка конфигурации: пароль БД лежит в томе
открытым текстом, и его ротация должна быть частой.
EOF
