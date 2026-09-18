#!/bin/sh
#
# Подготовка Seahub перед стартом контейнера seafile (k8s).
#
# 1) Подключает примонтированные seahub_oauth.py / seahub_onlyoffice.py в
#    seahub_settings.py (идемпотентно, по маркерам).
# 2) Накладывает код-патчи из /patches (идемпотентно: уже применённый патч
#    пропускается, расхождение контекста — громкая ошибка).
#
# Вызывается из command контейнера seafile перед оригинальным entrypoint.
# Все операции безопасно повторять при каждом старте пода.

set -eu

SHARED_CONF=/shared/seafile/conf
SETTINGS="$SHARED_CONF/seahub_settings.py"

wire_setting() {
  marker="$1"
  line="$2"
  [ -f "$SETTINGS" ] || return 0
  if grep -q "BEGIN HOMELAB $marker" "$SETTINGS"; then
    return 0
  fi
  printf '\n# BEGIN HOMELAB %s\n%s\n# END HOMELAB %s\n' "$marker" "$line" "$marker" >> "$SETTINGS"
  echo "wired: $marker"
}

wire_setting ONLYOFFICE 'exec(open("/shared/seafile/conf/seahub_onlyoffice.py").read())'
wire_setting OAUTH 'exec(open("/shared/seafile/conf/seahub_oauth.py").read())'

SEA_HOME="$(ls -d /opt/seafile/seafile-server-[0-9]*/seahub 2>/dev/null | head -1)"
if [ -z "$SEA_HOME" ]; then
  echo "ERROR: seahub dir not found under /opt/seafile" >&2
  exit 1
fi

for p in /patches/*.patch; do
  [ -f "$p" ] || continue
  name="$(basename "$p")"
  out="$(patch --dry-run -p1 -d "$SEA_HOME" -i "$p" </dev/null 2>&1)" || true
  if printf '%s' "$out" | grep -q "previously applied\|Skipping patch"; then
    echo "patch already applied: $name"
  elif printf '%s' "$out" | grep -q "FAILED\|mismatch\|Reversed"; then
    echo "ERROR: patch context mismatch (новая версия Seafile?): $name" >&2
    printf '%s\n' "$out" >&2
    exit 1
  elif patch -N -p1 -d "$SEA_HOME" -i "$p" </dev/null >/dev/null 2>&1; then
    echo "applied patch: $name"
  else
    echo "ERROR: failed to apply patch: $name" >&2
    exit 1
  fi
done

echo "seahub prepared"
