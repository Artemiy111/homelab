#!/usr/bin/env bash

# Оркестратор инициализации homelab: выполняет глобальную подготовку и
# запускает init.sh каждого сервиса (каталоги хранилища, .env, проверка
# Compose-конфигурации). Отдельный сервис можно инициализировать напрямую:
#   bash traefik/init.sh

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Общий каталог мультимедиа, не привязанный к одному сервису.
mkdir -p /storage/media

docker network inspect traefiknet >/dev/null 2>&1 || docker network create traefiknet >/dev/null

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
  pocket-id
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
  paperless
)

for service in "${services[@]}"; do
  echo "==> $service"
  bash "$repo_root/$service/init.sh"
done

echo "Подготовка завершена. Пароли сохранены только в локальных .env сервера."
