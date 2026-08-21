#!/usr/bin/env bash
#
# Создать или сбросить PocketBase superuser панели Beszel (/_/).
#
# Использование (на сервере):
#   bash ./superuser.sh <email>
#
# Пароль генерируется случайным образом и печатается один раз — сохраните его.

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

email="${1:?использование: bash ./superuser.sh <email>}"
password="$(random_password)"

docker exec beszel /beszel superuser upsert "$email" "$password" >/dev/null
echo "Superuser: ${email}"
echo "Пароль: ${password} (сохраните — повторный запуск скрипта сбросит его)"
