#!/usr/bin/env bash
# Самотест правил .gitlint и scripts/gitlint_rules.py.
#
# Правила проверок — часть гейта, а не настройка инструмента: ошибка в них
# пропускает мусор в историю или блокирует корректный коммит. Таблица ниже
# фиксирует ожидаемый вердикт для каждого случая, включая осознанные отличия от
# commitlint (пустой scope и продолжение футера отклоняются).
#
#   ./scripts/gitlint-selftest.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if ! command -v gitlint >/dev/null 2>&1; then
  echo "gitlint не установлен (brew install gitlint) — самотест невозможен" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pad() {
  local out="" i=0
  while [ "$i" -lt "$1" ]; do
    out="${out}a"
    i=$((i + 1))
  done
  printf '%s' "$out"
}

header_70="fix(x): $(pad 62)"
header_71="fix(x): $(pad 63)"
header_70_pr="fix(x): $(pad 54) (#1234)"
header_71_pr="fix(x): $(pad 55) (#1234)"

cases=0
failures=0

check() {
  local expected="$1" message="$2" got
  cases=$((cases + 1))
  printf '%s\n' "$message" > "$tmp/message"
  if gitlint --msg-filename "$tmp/message" >/dev/null 2>&1; then
    got=pass
  else
    got=fail
  fi
  if [ "$got" = "$expected" ]; then
    return 0
  fi
  failures=$((failures + 1))
  printf 'не совпало: ожидалось %s, получено %s: %s\n' "$expected" "$got" "$(printf '%s' "$message" | tr '\n' '/')" >&2
}

check pass 'fix(x): add y'
check pass 'fix: add y'
check pass 'chore: drop dead Arcane references'
check pass 'feat(seafile): add backup job'
check pass 'fix(element): json web logs, coturn metrics (#537)'
check pass 'refactor(argocd)!: drop values repo'
check pass 'fix(x): add DoH support'
check pass 'fix(x): add Y'
check pass 'fix(x): `Eslint` configuration'
check pass "$header_70"
check pass "$header_70_pr"
check pass 'fix(x): add y

Refs #12'
check pass 'fix(x): add y

Refs #12
Reviewed-on: https://example.invalid/pr/1'
check pass 'fix(x): add y

BREAKING CHANGE: nope'
check pass 'fix(x): add y

see #12'

check fail 'added runner'
check fail 'feature(x): y'
check fail 'Feat(x): add y'
check fail 'fix(x) add y'
check fail 'fix(x): add y.'
check fail 'fix(x): ADD Y'
check fail 'fix(x): Add Y'
check fail 'fix(x): AddY'
check fail "$header_71"
check fail "$header_71_pr"
check fail 'fix(): add y'
check fail 'fix(x): add y

prose here'
check fail 'fix(x): add y

Refs #12
prose here'

if [ "$failures" -ne 0 ]; then
  printf 'правила gitlint разошлись с ожиданиями: %d из %d\n' "$failures" "$cases" >&2
  exit 1
fi

printf 'правила gitlint соответствуют ожиданиям (%d случаев)\n' "$cases"
