#!/bin/sh
# Подготовка перед стартом smbd: учётки и пароль.
#
# `smbpasswd -s` читает пароль из stdin, чтобы он не остался в списке
# процессов. В Kubernetes stdin initContainer'а недоступен напрямую, пароль
# приходит из Secret через env, а в пайп уходит уже развёрнутым в
# переменную оболочки: в `ps` и в `/proc/*/cmdline` значения нет.
set -eu

/scripts/ensure-users.sh

printf '%s\n%s\n' "$SMB_PASSWORD" "$SMB_PASSWORD" | smbpasswd -s -a storage

# smbpasswd может отработать без ошибки, не записав запись: база лежит на
# пустом томе пода, и при недоступном каталоге команда завершается успехом
# с пустой базой. Клиенты не смогут аутентифицироваться, и заметить это
# можно только по их жалобам — поэтому проверяем тут.
pdbedit -L | grep -q '^storage:' || {
  echo "samba-init: ОШИБКА: storage не появился в базе Samba (pdbedit -L)" >&2
  exit 1
}
echo "samba-init: учётка storage создана"
