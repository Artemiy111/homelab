#!/usr/bin/env bash

# Проверяет, что базовый домен homelab не захардкожен в рантайм-конфигах.
#
# Домен (example.com) может встречаться только в:
#   - scripts/lib/common.sh      — единственный источник правды (значение по умолчанию);
#   - scripts/check-domain.sh    — сам гвард (значение по умолчанию в $domain);
#   - *.env.example и *.tpl.*    — шаблоны, из которых init.sh генерирует конфиги;
#   - *.md и apps/structurizr/homelab.dsl — документация.
#
# Во всех остальных файлах (compose, config.yaml, services.yaml, monitors.json,
# init.sh, *.properties, *.conf, *.mjs и т.д.) домен обязан приходить из DOMAIN
# или из шаблона.

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

domain="${DOMAIN:-example.com}"

is_allowed() {
  local path="$1"
  case "$path" in
    scripts/lib/common.sh) return 0 ;;
    scripts/check-domain.sh) return 0 ;;
    apps/structurizr/homelab.dsl) return 0 ;;
    *.md) return 0 ;;
    *.env.example) return 0 ;;
    # config.env — трекаемые дефолты сервиса (публичная конфигурация).
    # Производные от DOMAIN значения сюда НЕ пишутся: они собираются
    # в compose.yaml/шаблонах, поэтому allowlist для них нет.
    *.tpl.*) return 0 ;;
  esac
  return 1
}

status=0
while IFS= read -r file; do
  if is_allowed "$file"; then
    continue
  fi
  echo "Захардкожен домен $domain в: $file"
  git grep -n -F "$domain" -- "$file"
  status=1
done < <(git grep -l -F "$domain" -- . || true)

if [[ "$status" -ne 0 ]]; then
  echo "Используй DOMAIN / шаблон вместо захардкоженного домена." >&2
fi
exit "$status"
