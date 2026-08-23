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
  netdata
  paperless
  vault
  navidrome
  lute
  immich
  local-ai
  home-assistant
)

for service in "${services[@]}"; do
  echo "==> $service"

  # Приоритет источников: корневой .env → config.env сервиса → секреты
  # из secrets.enc.env (sops exec-env, высший). Сервис без secrets.enc.env работает
  # без расшифровки; сервис без config.env — только с корневым .env.
  env_files="--env-file '$repo_root/.env'"
  if [[ -f "$repo_root/$service/config.env" ]]; then
    env_files+=" --env-file '$repo_root/$service/config.env'"
  fi

  # init.sh рендерит шаблоны (.tpl.*) и тоже нуждается в публичной
  # конфигурации — подгружаем её в окружение перед секретами.
  init_cmd="bash '$repo_root/$service/init.sh'"
  [[ -f "$repo_root/$service/config.env" ]] &&
    init_cmd="set -a && . '$repo_root/$service/config.env' && $init_cmd"

  if [[ -f "$repo_root/$service/secrets.enc.env" ]]; then
    sops exec-env "$repo_root/$service/secrets.enc.env" "$init_cmd"
    sops exec-env "$repo_root/$service/secrets.enc.env" \
      "docker compose --project-directory '$repo_root/$service' $env_files up -d --remove-orphans"
  else
    bash "$repo_root/$service/init.sh"
    docker compose \
      --project-directory "$repo_root/$service" \
      $env_files \
      up -d --remove-orphans
  fi
done

echo "Подготовка завершена. Пароли сохранены только в локальных .env сервера."
