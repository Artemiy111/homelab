#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

# Конфигурация и секреты приходят через окружение — их расшифровывает
# `sops exec-env traefik/secrets.enc.env` (это делает bootstrap-platform.sh;
# вручную см. scripts/compose-secrets.sh). Plaintext-файл .env не создаётся.
if [[ -z "${RFC2136_TSIG_SECRET:-}" ]]; then
  echo "Ошибка: секреты traefik не переданы в окружение." >&2
  echo "Запустите через: bash scripts/compose-secrets.sh traefik ..." >&2
  echo "или: sops exec-env traefik/secrets.enc.env -- bash traefik/init.sh" >&2
  exit 1
fi

mkdir -p "$APPS_STORAGE_PATH"/traefik/letsencrypt

if [[ -x "$APPS_STORAGE_PATH"/traefik/letsencrypt ]]; then
  if [[ ! -e "$APPS_STORAGE_PATH"/traefik/letsencrypt/acme.json ]]; then
    install -m 0600 /dev/null "$APPS_STORAGE_PATH"/traefik/letsencrypt/acme.json
  fi
else
  echo 'Пропуск: каталог Traefik ACME недоступен текущему пользователю'
fi

# Статический конфиг Traefik запекается из шаблона: домен берётся из
# DOMAIN (common.sh), email Let's Encrypt — из config.env сервиса.
render_template \
  "$repo_root/traefik/traefik.tpl.yaml" \
  "$repo_root/traefik/traefik.yaml"

compose_config "$repo_root/traefik"
