#!/usr/bin/env bash

# Оркестратор инициализации homelab: выполняет глобальную подготовку и
# запускает init.sh каждого сервиса (каталоги хранилища, .env, проверка
# Compose-конфигурации). Без аргументов инициализирует все сервисы;
# с аргументами — только перечисленные:
#   bash scripts/bootstrap-platform.sh            # все сервисы
#   bash scripts/bootstrap-platform.sh glitchtip  # один сервис
# Отдельный сервис можно инициализировать напрямую:
#   bash traefik/init.sh

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
    uptime-kuma
    3x-ui
    nextcloud
    seafile
    jellyfin
    jitsi
    talk-hpb
    forgejo
    authentik
    zitadel
    oauth2-proxy
    dawarich
    beszel
    arcane
    image-updates
    infisical
    restic
    pdf
    home
    code-server
    gatus
    glitchtip
    netdata
    victoria-metrics
    paperless
    vault
    navidrome
    lute
    immich
    local-ai
    home-assistant
  )
fi

source "$repo_root/scripts/lib/common.sh"

for service in "${services[@]}"; do
  echo "==> $service"
  service_bootstrap "$service"
done

echo "Подготовка завершена. Пароли сохранены только в локальных .env сервера."
