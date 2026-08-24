#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

# Каталоги данных сервиса.
HA_DATA_DIR="$APPS_STORAGE_PATH"/home-assistant
HA_CUSTOM_COMPONENTS_DIR="$HA_DATA_DIR"/custom_components

# Кастомная интеграция SSO (hass-oidc-auth): ставится не через HACS, а из
# релиза GitHub, чтобы версия контролировалась коммитом. Желаемая версия —
# в закоммиченном config.env, установленная — в файле-метке рядом с компонентом.
OIDC_COMPONENT_DIR="$HA_CUSTOM_COMPONENTS_DIR"/auth_oidc
OIDC_VERSION="${HOME_ASSISTANT_OIDC_VERSION:?set in home-assistant/config.env}"
OIDC_VERSION_STAMP="$HA_CUSTOM_COMPONENTS_DIR"/.hass-oidc-auth.version

ensure_dirs 0750 \
  "$HA_DATA_DIR" \
  "$HA_CUSTOM_COMPONENTS_DIR"

install_oidc_component() {
  local archive="/tmp/hass-oidc-auth-${OIDC_VERSION}.zip"

  echo "Установка hass-oidc-auth ${OIDC_VERSION}..."
  curl -fsSL -o "$archive" \
    "https://github.com/christiaangoossens/hass-oidc-auth/releases/download/${OIDC_VERSION}/hass-oidc-auth.zip"
  rm -rf "$OIDC_COMPONENT_DIR"
  unzip -q -o "$archive" -d "$HA_CUSTOM_COMPONENTS_DIR"
  rm -f "$archive"
  test -f "$OIDC_COMPONENT_DIR/manifest.json"
  printf '%s\n' "$OIDC_VERSION" >"$OIDC_VERSION_STAMP"
}

if [[ "$(cat "$OIDC_VERSION_STAMP" 2>/dev/null || true)" == "$OIDC_VERSION" ]]; then
  echo "hass-oidc-auth ${OIDC_VERSION} уже установлен."
else
  install_oidc_component
fi

compose_config "$repo_root/home-assistant"
