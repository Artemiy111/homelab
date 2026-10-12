#!/bin/sh
# Проверяет, что verify-mounts.sh действительно останавливает под.
#
# Тест родился из конкретного дефекта. Проверка читала список томов через
# конвейер (`echo "$SHARES" | while read ...`), поэтому цикл исполнялся в
# подпроцессе. Флаг `failed` выставлялся внутри него и наружу не доходил,
# внешний скрипт возвращал ноль — initContainer пропускал под, `smbd`
# поднимался и отдавал пустую шару. Ровно та поломка, ради которой проверка
# написана.
#
# Сценарий «каталога нет» ловится и старой версией случайно: `fail` завершает
# подпроцесс с кодом 1, а конвейер возвращает код последней команды. Дефект
# живёт в ветке «каталог есть, но смонтировано не то» — её и проверяем.
#
# Ожидания берутся из самого проверяемого скрипта: имена томов, режимы и UUID
# читаются из его `SHARES`, серийники считаются из UUID тем же преобразованием.
# Иначе тест пришлось бы править при каждой замене диска, и однажды он
# разошёлся бы с продакшеном молча — ровно так и случилось при смене UUID ntfs1.
#
# Скрипт исполняется как есть, без правок в продакшене: пути подменяются
# копией в temp, а `stat` — заглушкой в PATH.
set -eu

script="${1:-$(dirname "$0")/../manifests/config/verify-mounts.sh}"
[ -f "$script" ] || { echo "тест: не найден $script" >&2; exit 1; }

# точка:режим:UUID — то, что проверка требует от хоста.
shares() {
  sed -n '/^SHARES="/,/"/p' "$script" | tr -d '"' | sed 's/^SHARES=//' |
    awk 'NF >= 3 && $1 ~ /^ntfs[0-9]+$/ { print $1, $2, $3 }'
}

uuid_to_serial() {
  echo "$1" | sed -E 's/^(....)(....)(....)(....)$/\3\4\1\2/' | tr 'A-F' 'a-f'
}

first="$(shares | awk 'NR == 1 { print $1 }')"
second="$(shares | awk 'NR == 2 { print $1 }')"
last="$(shares | awk 'NR == 3 { print $1 }')"
[ -n "$first" ] && [ -n "$second" ] && [ -n "$last" ] ||
  { echo "тест: не удалось прочитать SHARES из $script" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/mnt" "$tmp/bin"
shares | while read -r name _ _; do mkdir -p "$tmp/mnt/$name"; done

cp "$script" "$tmp/verify-mounts.sh"
sed -e "s|/proc/self/mounts|$tmp/mounts|g" \
    -e "s|/mnt/|$tmp/mnt/|g" \
    "$tmp/verify-mounts.sh" > "$tmp/verify.sh"
chmod +x "$tmp/verify.sh"

cat > "$tmp/bin/stat" <<'STUB'
#!/bin/sh
path="$2"
id="$(awk -v p="$path" '$1 == p { print $2 }' "$STUB_IDS")"
echo "  File: \"$path\""
echo "    ID: $id Namelen: 255     Type: UNKNOWN"
STUB
chmod +x "$tmp/bin/stat"
export STUB_IDS="$tmp/ids"
export PATH="$tmp/bin:$PATH"

# Все тома смонтированы верно: ntfs3, режимы и серийники совпадают с SHARES.
mounts_ok() {
  : > "$tmp/mounts"
  : > "$tmp/ids"
  shares | while read -r name mode uuid; do
    printf '/dev/sdX %s ntfs3 %s,noatime,context=x 0 0\n' "$tmp/mnt/$name" "$mode" >> "$tmp/mounts"
    printf '%s %s\n' "$tmp/mnt/$name" "$(uuid_to_serial "$uuid")" >> "$tmp/ids"
  done
}

# Правка файла на месте без `sed -i`: у BSD и GNU разные требования к
# аргументу `-i`, а `-i.bak` оставляет файлы бэкапа. Запись через
# промежуточный файл переносима и мусора не создаёт.
subst() {
  sed "$2" "$1" > "$1.new"
  mv "$1.new" "$1"
}

expect_ok() {
  mounts_ok
  rc=0
  out="$("$tmp/verify.sh" 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] || { echo "тест: ожидался успех, получен код $rc: $out" >&2; exit 1; }
}

expect_reject() {
  desc="$1"
  rc=0
  out="$("$tmp/verify.sh" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "тест: $desc — скрипт вернул 0, под не остановлен" >&2
    echo "тест: вывод: $out" >&2
    exit 1
  fi
  case "$out" in
    *"samba-init: ОШИБКА"*) ;;
    *) echo "тест: $desc — нет внятного сообщения, вывод: $out" >&2; exit 1 ;;
  esac
}

# Все тома смонтированы верно.
expect_ok

# Тома нет: точка — каталог корневого раздела, а не том NTFS.
rm -rf "${tmp:?}/mnt/$second"
expect_reject "отсутствующий том"

# Каталог есть, но под ним корневой раздел хоста, а не NTFS. Это и есть
# сценарий, который старая версия пропускала.
mkdir -p "$tmp/mnt/$second"
mounts_ok
subst "$tmp/mounts" "s|\($tmp/mnt/$second\) ntfs3 |\1 xfs |"
expect_reject "xfs вместо ntfs3"

# Режим разошёлся с SHARES: том смонтирован ro, а объявлен rw.
mounts_ok
subst "$tmp/mounts" "s|\($tmp/mnt/$second ntfs3 \)ro|\1rw|"
expect_reject "режим не совпал"

# Серийник не тот: другой диск даёт тот же fstype и тот же режим.
mounts_ok
subst "$tmp/ids" "s|^\($tmp/mnt/$last\) .*|\1 deadbeefdeadbeef|"
expect_reject "другой диск"

# Отказ на последнем томе тоже валит под: цель — отсутствие шар, а не
# максимальное число проверенных томов.
mounts_ok
rm -rf "${tmp:?}/mnt/$last"
expect_reject "отсутствует последний том"

echo "тест: проверка отвергает все проверенные поломки"
