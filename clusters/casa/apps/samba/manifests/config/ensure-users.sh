#!/bin/sh
# Unix-учётки для smbd и каталоги состояния на пустом томе пода.
#
# `smbpasswd -a` отказывает с «Failed to add entry», если учётки нет в
# /etc/passwd: база tdbsam хранит только пароль, а привязка к системной
# учётке обязательна. Это технические аккаунты, вход невозможен; файлами
# они не владеют — за это отвечает `force user` в секциях шар.
#
# `ops` — не копия хоста: в кластере важны только uid/gid 1000, которые
# синтезирует ntfs3 из опций монтирования. Имя оставлено тем же, чтобы
# конфиг шар совпадал с хостовым и владелец файлов читался одинаково в
# `kubectl exec` и в `ls` на узле.
set -eu

for d in /var/lib/samba/private /var/lib/samba/state /var/lib/samba/cache /var/lib/samba/lockdir; do
  mkdir -p "$d"
done

getent group ops >/dev/null 2>&1 || addgroup -g 1000 ops
getent passwd ops >/dev/null 2>&1 || adduser -D -H -u 1000 -G ops -s /sbin/nologin ops
getent passwd storage >/dev/null 2>&1 || adduser -D -H -s /sbin/nologin storage
