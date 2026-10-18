#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if [ "${1:---check}" != "--check" ]; then
  printf 'использование: %s --check\n' "$0" >&2
  exit 2
fi

manifest="apps/casa/grafana/manifests/alerts.yaml"
registry="apps/casa/grafana/README.md"

failures=0

fail() {
  printf '%s\n' "$1" >&2
  failures=$((failures + 1))
}

has_uid() {
  printf '%s\n' "$1" | grep -qx -- "$2"
}

manifest_uids="$(sed -n 's/^    - uid: \(.*\)$/\1/p' "$manifest" | sort)"
registry_uids="$(grep -o '^| `[a-z0-9][a-z0-9-]*`' "$registry" | tr -d '|` ' | sort)"
runbook_uids="$(grep -rhE '^### (`[a-z0-9][a-z0-9-]*`[ /,]*)+$' apps/casa platform/casa --include='RUNBOOK.md' \
  | grep -oE '`[a-z0-9][a-z0-9-]*`' | tr -d '`' | sort -u)"

if [ -z "$manifest_uids" ]; then
  fail "$manifest: правила не найдены"
fi

while IFS= read -r uid; do
  [ -n "$uid" ] || continue
  has_uid "$registry_uids" "$uid" ||
    fail "$uid: правило есть в манифесте, но не в таблице $registry"
done <<<"$manifest_uids"

while IFS= read -r uid; do
  [ -n "$uid" ] || continue
  has_uid "$manifest_uids" "$uid" ||
    fail "$uid: описан в $registry, но такого правила нет в $manifest"
done <<<"$registry_uids"

while IFS= read -r uid; do
  [ -n "$uid" ] || continue
  has_uid "$manifest_uids" "$uid" ||
    fail "$uid: раздел в RUNBOOK, но такого правила нет в $manifest"
done <<<"$runbook_uids"

if [ "$failures" -ne 0 ]; then
  printf 'несоответствий: %d\n' "$failures" >&2
  exit 1
fi

printf 'правил в манифесте: %s; реестр и разделы RUNBOOK согласованы\n' \
  "$(printf '%s\n' "$manifest_uids" | grep -c .)"
