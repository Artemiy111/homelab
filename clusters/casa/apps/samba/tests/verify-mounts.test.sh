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
# Скрипт исполняется как есть, без правок в продакшене: пути подменяются
# копией в temp, а `stat` — заглушкой в PATH.
set -eu

script="${1:-$(dirname "$0")/../manifests/config/verify-mounts.sh}"
[ -f "$script" ] || { echo "тест: не найден $script" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/mnt/ntfs1" "$tmp/mnt/ntfs2" "$tmp/mnt/ntfs3" "$tmp/bin"
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

# Три тома смонтированы верно: ntfs3, режимы и серийники совпадают с fstab.
mounts_ok() {
  cat > "$tmp/mounts" <<EOF
/dev/sdbc1 $tmp/mnt/ntfs1 ntfs3 rw,noatime,context=x 0 0
/dev/sdbc2 $tmp/mnt/ntfs2 ntfs3 ro,noatime,context=x 0 0
/dev/sdbc3 $tmp/mnt/ntfs3 ntfs3 rw,noatime,context=x 0 0
EOF
  cat > "$tmp/ids" <<EOF
$tmp/mnt/ntfs1 5209d6524e17ffbc
$tmp/mnt/ntfs2 909097a6f49090cd
$tmp/mnt/ntfs3 2a2dc9d7962a2dec
EOF
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

mounts_ok

# Том смонтирован верно.
expect_ok

# Тома нет: точка — каталог корневого раздела, а не том NTFS.
rm -rf "$tmp/mnt/ntfs2"
expect_reject "отсутствующий том"

# Каталог есть, но под ним корневой раздел хоста, а не NTFS. Это и есть
# сценарий, который старая версия пропускала.
mkdir -p "$tmp/mnt/ntfs2"
mounts_ok
sed -i.bak "s|^/dev/sdbc2 $tmp/mnt/ntfs2 ntfs3|/dev/sdbc2 $tmp/mnt/ntfs2 xfs|" "$tmp/mounts"
expect_reject "xfs вместо ntfs3"

# Режим разошёлся с fstab: том смонтирован ro, а объявлен rw.
mounts_ok
sed -i.bak "s|^/dev/sdbc2 $tmp/mnt/ntfs2 ntfs3 ro|/dev/sdbc2 $tmp/mnt/ntfs2 ntfs3 rw|" "$tmp/mounts"
expect_reject "режим не совпал"

# Серийник не тот: другой диск даёт тот же fstype и тот же режим.
mounts_ok
sed -i.bak "s|^$tmp/mnt/ntfs3 .*|$tmp/mnt/ntfs3 deadbeefdeadbeef|" "$tmp/ids"
expect_reject "другой диск"

# Отказ на последнем томе тоже валит под: цель — отсутствие шар, а не
# максимальное число проверенных томов.
mounts_ok
rm -rf "$tmp/mnt/ntfs3"
expect_reject "отсутствует последний том"

echo "тест: проверка отвергает все проверенные поломки"
