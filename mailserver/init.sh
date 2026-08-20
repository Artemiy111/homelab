#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 \
  "$APPS_STORAGE_PATH"/mailserver \
  "$APPS_STORAGE_PATH"/mailserver/etc \
  "$APPS_STORAGE_PATH"/mailserver/data \
  "$APPS_STORAGE_PATH"/mailserver/mail

# Контейнеры работают под не-владельческими uid: Stalwart — 2000
# (etc, data), Bulwark — 1001 (mail). Открываем доступ: при root — chown,
# иначе — ACL для конкретного uid (не требует root).
_grant_access() {
  local uid="$1"
  shift
  if [[ $EUID -eq 0 ]]; then
    chown -R "$uid:$uid" "$@"
  elif command -v setfacl >/dev/null; then
    setfacl -m "u:$uid:rwx" -d -m "u:$uid:rwx" "$@"
  else
    echo "Внимание: setfacl недоступен; uid $uid не получит доступ к: $*" >&2
  fi
}

_grant_access 2000 "$APPS_STORAGE_PATH"/mailserver/etc "$APPS_STORAGE_PATH"/mailserver/data
_grant_access 1001 "$APPS_STORAGE_PATH"/mailserver/mail

write_env_file "$repo_root/mailserver/.env" <<EOF
MAILSERVER_HOST=mailserver.$DOMAIN
MAIL_HOST=mail.$DOMAIN
STALWART_ADMIN_USER=admin
STALWART_ADMIN_PASS=$(random_secret)
EOF

compose_config "$repo_root/mailserver"
