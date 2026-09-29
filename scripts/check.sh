#!/usr/bin/env bash
# Локальные проверки одной командой — то, что гоняет .githooks/pre-commit,
# плюс статический анализ, который до коммита не нужен.
#
# Хуков может не быть: core.hooksPath настраивается один раз на клон, и если он
# не настроен, git молча ничего не выполняет. Поэтому проверки живут здесь, а
# хуки вызывают именно их; расхождение пути печатается как предупреждение, а не
# остаётся тихим.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

failures=0

step() {
  local what="$1"
  shift
  printf '== %s\n' "$what"
  if "$@"; then
    printf '   ok\n'
  else
    printf '   FAIL: %s\n' "$what" >&2
    failures=$((failures + 1))
  fi
}

optional() {
  local tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    return 0
  fi
  printf 'warn: %s не установлен — проверка пропущена\n' "$tool" >&2
  return 1
}

hooks_path="$(git config --get core.hooksPath || true)"
if [ "$hooks_path" != ".githooks" ]; then
  printf 'warn: core.hooksPath=%s, хуки не выполняются. Включить: git config core.hooksPath .githooks\n' \
    "${hooks_path:-<не задан>}" >&2
fi

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "gitleaks не установлен (brew install gitleaks) — проверка невозможна" >&2
  exit 1
fi

# Секреты ищем в объектах git, а не обходом каталога: `gitleaks dir` заходит в
# .worktrees/ и packages/, которые игнорируются репозиторием, и даёт ложные
# срабатывания — path-анкерованные allowlist из .gitleaks.toml перестают
# совпадать, а чужие фикстуры из packages/ попадают в чужой скан. Тот же
# подход, что в гейте secrets.yml: только то, что может попасть в историю.

step "секреты в staged" gitleaks git --staged --config .gitleaks.toml --no-banner --redact
step "секреты в коммитах ветки" gitleaks git --config .gitleaks.toml --no-banner --redact \
  --log-opts="origin/main..HEAD"
step "числа в docs/status соответствуют репозиторию" ./scripts/status-badges.sh --check

if optional shellcheck; then
  # bash 3.2 на macOS не знает mapfile, поэтому массив собирается циклом.
  scripts=()
  # Те же исключения, что и в .forgejo/workflows/shellcheck.yml: .agents и
  # .claude — шаблоны скиллов и инструментовка, не код репозитория.
  while IFS= read -r file; do
    scripts+=("$file")
  done < <(git ls-files -- '*.sh' '.githooks/*' ':!.agents/**' ':!.claude/**')
  step "shellcheck (${#scripts[@]} файлов)" shellcheck -S warning "${scripts[@]}"
fi

if optional actionlint; then
  step "actionlint" actionlint -config-file .forgejo/actionlint.yaml .forgejo/workflows/*.yml
fi

if optional commitlint; then
  step "сообщение последнего коммита" commitlint --last
fi

if [ "$failures" -ne 0 ]; then
  printf 'провалено проверок: %d\n' "$failures" >&2
  exit 1
fi
printf 'все локальные проверки пройдены\n'
