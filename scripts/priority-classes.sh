#!/usr/bin/env bash
# Политика приоритетов: класс, на который ссылается манифест, обязан быть
# объявлен в юните priorityclasses. Ссылка на несуществующий класс не
# игнорируется: admission-контроллер Priority отклоняет создание пода, и
# опечатка в имени класса выглядит как необъяснимый отказ развернуться, а не
# как предупреждение. Глобальный дефолт запрещён осознанно: он молча назначает
# класс подам без явного, а смена значения действует только на созданные позже.
#
#   ./scripts/priority-classes.sh --check
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

classes_file="clusters/casa/platform/priorityclasses/manifests/priorityclasses.yaml"

# Классы, объявленные не нами: их создают Kubernetes и чарт Longhorn.
external=" system-node-critical system-cluster-critical longhorn-critical "

declared="$(
  awk '
    /^kind: PriorityClass$/ { doc = 1; next }
    /^apiVersion:/ { doc = 0 }
    doc && /^  name: / { print $2; doc = 0 }
  ' "$classes_file" | sort -u
)"

failures=0

used="$(
  git ls-files 'clusters/casa/*.yaml' 'bootstrap/*.yaml' |
    grep -v "^${classes_file}$" |
    xargs -r grep -hoE 'priorityClassName:[[:space:]]*"?[A-Za-z0-9][A-Za-z0-9.-]*' |
    sed -E 's/^priorityClassName:[[:space:]]*"?([A-Za-z0-9][A-Za-z0-9.-]*).*$/\1/' |
    sort -u || true
)"

for name in $used; do
  case "$external" in
    *" $name "*) continue ;;
  esac
  if ! grep -qx "$name" <<<"$declared"; then
    printf 'ссылка на необъявленный класс: %s (%s)\n' "$name" "$classes_file" >&2
    failures=$((failures + 1))
  fi
done

if grep -qE '^globalDefault:[[:space:]]*true' "$classes_file"; then
  printf 'globalDefault: true запрещён: он молча назначает класс подам без явного (%s)\n' \
    "$classes_file" >&2
  failures=$((failures + 1))
fi

classes="$(printf '%s\n' "$declared" | grep -c . || true)"
explicit="$(grep -cE '^globalDefault:[[:space:]]*false' "$classes_file" || true)"
if [ "$classes" -ne "$explicit" ]; then
  printf 'у каждого класса globalDefault обязан быть задан явно: классов %s, полей %s (%s)\n' \
    "$classes" "$explicit" "$classes_file" >&2
  failures=$((failures + 1))
fi

if [ "$failures" -ne 0 ]; then
  printf 'нарушений политики приоритетов: %d\n' "$failures" >&2
  exit 1
fi

printf 'классов объявлено — %s, ссылок из манифестов — %s\n' \
  "$classes" "$(printf '%s\n' "$used" | grep -c . || true)"
