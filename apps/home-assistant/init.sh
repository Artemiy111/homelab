#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

SERVICE_DIR="$repo_root"/apps/home-assistant
OIDC_VERSION="${HOME_ASSISTANT_OIDC_VERSION:?set in home-assistant/config.env}"
OIDC_DIR="$SERVICE_DIR"/custom_components/auth_oidc
OIDC_STAMP="$SERVICE_DIR"/custom_components/.hass-oidc-auth.version

export TZ="${TZ:-Asia/Yekaterinburg}"

# Интеграция SSO ставится из релиза GitHub в маунт-каталог сервиса; версия
# пинируется в закоммиченном config.env. Повторный запуск с той же версией —
# no-op, с новой — обновление.
if [[ "$(cat "$OIDC_STAMP" 2>/dev/null || true)" != "$OIDC_VERSION" ]]; then
  echo "Установка hass-oidc-auth ${OIDC_VERSION}..."
  curl -fsSL -o /tmp/hass-oidc-auth.zip \
    "https://github.com/christiaangoossens/hass-oidc-auth/releases/download/${OIDC_VERSION}/hass-oidc-auth.zip"
  rm -rf "$OIDC_DIR"
  # Содержимое релиза лежит в корне архива — это и есть auth_oidc/.
  mkdir -p "$OIDC_DIR"
  unzip -q /tmp/hass-oidc-auth.zip -d "$OIDC_DIR"
  rm /tmp/hass-oidc-auth.zip
  test -f "$OIDC_DIR/manifest.json"
  echo "$OIDC_VERSION" >"$OIDC_STAMP"
else
  echo "hass-oidc-auth ${OIDC_VERSION} уже установлен."
fi

# Секреты никуда на диск не пишутся: они приходят в контейнер окружением
# (secrets.enc.env расшифровывается service_compose через service_run),
# configuration.yaml читает их через !env_var.

compose_config "$SERVICE_DIR"
