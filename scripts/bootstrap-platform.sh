#!/usr/bin/env bash

# Оркестратор инициализации homelab: выполняет глобальную подготовку и
# запускает init.sh каждого сервиса (каталоги хранилища, .env, проверка
# Compose-конфигурации). Без аргументов инициализирует все сервисы;
# с аргументами — только перечисленные:
#   bash scripts/bootstrap-platform.sh            # все сервисы
#   bash scripts/bootstrap-platform.sh glitchtip  # один сервис
# Отдельный сервис можно инициализировать напрямую:
#   bash apps/traefik/init.sh

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Общий каталог мультимедиа, не привязанный к одному сервису.
mkdir -p /storage/media

docker network inspect traefiknet >/dev/null 2>&1 || docker network create traefiknet >/dev/null

if [[ $# -gt 0 ]]; then
  services=("$@")
else
  services=(
    traefik
    technitium
    3x-ui
    arcane
    authentik
    beszel
    code-server
    dawarich
    element
    forgejo
    gatus
    glitchtip
    home
    home-assistant
    image-updates
    immich
    infisical
    jellyfin
    jitsi
    local-ai
    lute
    mermaid-live-editor
    navidrome
    netdata
    nextcloud
    open-webui
    oauth2-proxy
    paperless
    pdf
    restic
    rustfs
    seafile
    structurizr
    sure
    talk-hpb
    uptime-kuma
    vault
    victoria-metrics
    zitadel
  )
fi

source "$repo_root/scripts/lib/common.sh"

for service in "${services[@]}"; do
  echo "==> $service"
  service_bootstrap "$service"
done

echo "Подготовка завершена. Секреты хранятся зашифрованно в apps/<сервис>/secrets.enc.env."
