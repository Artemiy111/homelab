#!/bin/sh
# Главная проверка задачи: hostPath в Kubernetes не знает про монтирования
# хоста. Если том не смонтирован, точка монтирования — пустой каталог на
# корневом разделе, под стартует, smb работает, шара открывается пустой, без
# единой ошибки. Клиент решит, что данные пропали.
#
# Три независимых признака, каждый по отдельности недостаточен:
#
#   1. fstype == ntfs3. Точка без тома видна в /proc/self/mounts как `xfs`
#      (корневой раздел хоста) — это и есть «каталог вместо тома».
#   2. Режим ro/rw совпадает с описанием тома. `read only = yes` в секции
#      шары не мешает ядру: клиент получит ошибку ввода-вывода вместо
#      внятного «read-only resource».
#   3. Серийный номер тома совпадает с UUID из fstab. Другой диск даёт тот
#      же fstype и тот же режим — отличает только номер.
#
# Номер выводит `stat -f` (`ID`), и он совпадает с UUID из fstab с
# переставленными половинками: ntfs3 печатает серийник в порядке байт,
# противоположном порядку в UUID.
set -eu

# точка:режим:UUID — значения из /etc/fstab хоста
SHARES="ntfs1 ro 36447F8E447F4F9B
ntfs2 ro F49090CD909097A6
ntfs3 rw 962A2DEC2A2DC9D7"

uuid_to_serial() {
  echo "$1" | sed -E 's/^(....)(....)(....)(....)$/\3\4\1\2/' | tr 'A-F' 'a-f'
}

fail() {
  echo "samba-init: ОШИБКА: $*" >&2
  exit 1
}

# `while read` в конвейере исполняется в подпроцессе, поэтому `exit 1`
# внутри него не остановит скрипт. Флаг наружу — единственный способ
# сохранить код возврата.
failed=0

echo "$SHARES" | while read -r name mode uuid; do
  [ -n "$name" ] || continue
  path="/mnt/$name"

  [ -d "$path" ] || fail "$name: точка $path не существует"

  line="$(awk -v p="$path" '$2 == p { line = $0 } END { print line }' /proc/self/mounts)"
  if [ -z "$line" ]; then
    echo "samba-init: ОШИБКА: $name: $path не смонтирован — в /proc/self/mounts нет записи с таким mountpoint. Том NTFS не подключён или не смонтирован." >&2
    failed=1
    continue
  fi

  fstype="$(echo "$line" | awk '{ print $3 }')"
  if [ "$fstype" != "ntfs3" ]; then
    echo "samba-init: ОШИБКА: $name: $path смонтирован как '$fstype', ожидался ntfs3. Это каталог корневого раздела, а не том NTFS: шара была бы пустой." >&2
    failed=1
    continue
  fi

  opts="$(echo "$line" | awk '{ print $4 }')"
  case ",$opts," in
    *",$mode,"*) ;;
    *)
      echo "samba-init: ОШИБКА: $name: $path смонтирован с режимом '$opts', ожидался '$mode'. Расхождение с fstab." >&2
      failed=1
      continue
      ;;
  esac

  serial="$(stat -f "$path" | awk '/ID:/ { print $2 }')"
  want="$(uuid_to_serial "$uuid")"
  if [ "$serial" != "$want" ]; then
    echo "samba-init: ОШИБКА: $name: в точке $path том '$serial', а ожидался '$want' (UUID $uuid). Это не тот диск." >&2
    failed=1
    continue
  fi

  echo "samba-init: $name на месте: ntfs3, $mode, том $serial"
done

[ "$failed" -eq 0 ] || exit 1
