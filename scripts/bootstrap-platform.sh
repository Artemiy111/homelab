#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

random_secret() {
  openssl rand -hex 24
}

create_traefik_env() {
  local env_file="$repo_root/traefik/.env"
  if [[ -e "$env_file" ]]; then
    echo "Пропуск: $env_file уже существует"
    return
  fi

  local password hash
  password="$(random_secret)"
  hash="$(printf '%s' "$password" | openssl passwd -apr1 -stdin)"

  umask 077
  {
    echo 'TRAEFIK_HOST=traefik.example.net'
    echo 'TRAEFIK_DASHBOARD_USERNAME=admin'
    printf 'TRAEFIK_DASHBOARD_PASSWORD=%s\n' "$password"
    printf "TRAEFIK_DASHBOARD_USERS='admin:%s'\n" "$hash"
    echo 'RFC2136_NAMESERVER=ns1.<dns-provider>.com:53'
    echo 'RFC2136_TSIG_ALGORITHM=hmac-sha256.'
    echo 'RFC2136_TSIG_KEY=replace-with-the-<dns-provider>-tsig-key-name'
    echo 'RFC2136_TSIG_SECRET=replace-with-the-<dns-provider>-tsig-secret'
  } >"$env_file"
}

create_pihole_env() {
  local env_file="$repo_root/pihole/.env"
  if [[ -e "$env_file" ]]; then
    echo "Пропуск: $env_file уже существует"
    return
  fi

  umask 077
  {
    echo 'PIHOLE_HOST=pihole.example.net'
    printf 'PIHOLE_ADMIN_PASSWORD=%s\n' "$(random_secret)"
  } >"$env_file"
}

create_uptime_kuma_env() {
  local env_file="$repo_root/uptime-kuma/.env"
  if [[ -e "$env_file" ]]; then
    echo "Пропуск: $env_file уже существует"
    return
  fi

  umask 077
  {
    echo 'UPTIME_KUMA_HOST=uptime.example.net'
    echo 'UPTIME_KUMA_USERNAME=user'
    echo 'UPTIME_KUMA_PASSWORD='
  } >"$env_file"
}

create_3x_ui_env() {
  local env_file="$repo_root/3x-ui/.env"
  if [[ -e "$env_file" ]]; then
    echo "Пропуск: $env_file уже существует"
    return
  fi

  umask 077
  {
    echo 'XUI_HOST=xui.example.net'
    echo 'XUI_ADMIN_USERNAME=xui-admin'
    printf 'XUI_ADMIN_PASSWORD=%s\n' "$(random_secret)"
    printf 'XUI_WEB_BASE_PATH=/panel-%s/\n' "$(openssl rand -hex 12)"
    echo 'XUI_INBOUND_PORT=8443'
  } >"$env_file"
}

create_nextcloud_env() {
  local env_file="$repo_root/nextcloud/.env"
  if [[ -e "$env_file" ]]; then
    echo "Пропуск: $env_file уже существует"
    return
  fi

  local traefik_network_cidr
  traefik_network_cidr="$(
    docker network inspect traefiknet \
      --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
  )"

  umask 077
  {
    echo 'NEXTCLOUD_HOST=nextcloud.example.net'
    echo 'NEXTCLOUD_ADMIN_USER=nextcloud-admin'
    printf 'NEXTCLOUD_ADMIN_PASSWORD=%s\n' "$(random_secret)"
    echo 'POSTGRES_DB=nextcloud'
    echo 'POSTGRES_USER=nextcloud'
    printf 'POSTGRES_PASSWORD=%s\n' "$(random_secret)"
    printf 'TRAEFIK_NETWORK_CIDR=%s\n' "$traefik_network_cidr"
    echo 'TZ=Asia/Yekaterinburg'
  } >"$env_file"
}

create_jellyfin_env() {
  local env_file="$repo_root/jellyfin/.env"
  if [[ -e "$env_file" ]]; then
    echo "Пропуск: $env_file уже существует"
    return
  fi

  local render_group_id
  render_group_id="$(getent group render | cut -d: -f3)"
  if [[ -z "$render_group_id" ]]; then
    echo 'Не найдена группа render для Jellyfin' >&2
    return 1
  fi

  umask 077
  {
    echo 'JELLYFIN_HOST=jellyfin.example.net'
    printf 'JELLYFIN_RENDER_GROUP_ID=%s\n' "$render_group_id"
  } >"$env_file"
}

create_gitea_env() {
  local env_file="$repo_root/gitea/.env"
  if [[ -e "$env_file" ]]; then
    echo "Пропуск: $env_file уже существует"
    return
  fi

  local traefik_network_cidr
  traefik_network_cidr="$(
    docker network inspect traefiknet \
      --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
  )"

  umask 077
  {
    echo 'GITEA_HOST=gitea.example.net'
    echo 'GITEA_SSH_PORT=2222'
    echo 'POSTGRES_DB=gitea'
    echo 'POSTGRES_USER=gitea'
    printf 'POSTGRES_PASSWORD=%s\n' "$(random_secret)"
    echo 'GITEA_ADMIN_USERNAME=gitea-admin'
    printf 'GITEA_ADMIN_PASSWORD=%s\n' "$(random_secret)"
    echo 'GITEA_ADMIN_EMAIL=gitea-admin@example.invalid'
    printf 'TRAEFIK_NETWORK_CIDR=%s\n' "$traefik_network_cidr"
    echo 'TZ=Asia/Yekaterinburg'
  } >"$env_file"
}

create_pocket_id_env() {
  local env_file="$repo_root/pocket-id/.env"
  if [[ -e "$env_file" ]]; then
    echo "Пропуск: $env_file уже существует"
    return
  fi

  local traefik_network_cidr puid pgid
  traefik_network_cidr="$(
    docker network inspect traefiknet \
      --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
  )"
  puid="$(id -u)"
  pgid="$(id -g)"

  umask 077
  {
    echo 'POCKET_ID_HOST=id.example.net'
    printf 'ENCRYPTION_KEY=%s\n' "$(openssl rand -base64 32)"
    printf 'TRAEFIK_NETWORK_CIDR=%s\n' "$traefik_network_cidr"
    printf 'PUID=%s\n' "$puid"
    printf 'PGID=%s\n' "$pgid"
  } >"$env_file"
}

create_dawarich_env() {
  local env_file="$repo_root/dawarich/.env"
  if [[ -e "$env_file" ]]; then
    echo "Пропуск: $env_file уже существует"
    return
  fi

  umask 077
  {
    echo 'DAWARICH_HOST=dawarich.example.net'
    echo 'DAWARICH_VERSION=1.11.0'
    echo 'POSTGRES_DB=dawarich_production'
    echo 'POSTGRES_USER=dawarich'
    printf 'POSTGRES_PASSWORD=%s\n' "$(random_secret)"
    printf 'SECRET_KEY_BASE=%s\n' "$(openssl rand -hex 64)"
    echo 'TZ=Asia/Yekaterinburg'
    echo 'WEB_CONCURRENCY=1'
    echo 'BACKGROUND_PROCESSING_CONCURRENCY=3'
    echo 'APP_CPU_LIMIT=0.50'
    echo 'APP_MEMORY_LIMIT=4G'
    echo 'LOG_MAX_SIZE=100m'
    echo 'LOG_MAX_FILE=5'
  } >"$env_file"
}

create_beszel_env() {
  local env_file="$repo_root/beszel/.env"
  if [[ -e "$env_file" ]]; then
    echo "Пропуск: $env_file уже существует"
    return
  fi

  umask 077
  {
    echo 'BESZEL_HOST=beszel.example.net'
    echo 'BESZEL_AGENT_KEY='
    echo 'BESZEL_AGENT_TOKEN='
  } >"$env_file"
}

create_restic_env() {
  local env_file="$repo_root/restic/.env"
  if [[ -e "$env_file" ]]; then
    echo "Пропуск: $env_file уже существует"
    return
  fi

  umask 077
  {
    printf 'RESTIC_PASSWORD=%s\n' "$(random_secret)"
    echo 'BACKUP_SOURCE=/storage/apps'
    echo "CONFIG_SOURCE=$repo_root"
    echo 'RESTIC_REPOSITORY_PATH=/storage/backups/restic'
  } >"$env_file"
}

mkdir -p \
  /storage/apps/3x-ui/db \
  /storage/apps/3x-ui/log \
  /storage/apps/pihole/etc-pihole \
  /storage/apps/nextcloud/backups \
  /storage/apps/nextcloud/html \
  /storage/apps/nextcloud/postgresql \
  /storage/apps/nextcloud/redis \
  /storage/apps/jellyfin/config \
  /storage/apps/jellyfin/cache \
  /storage/apps/gitea/backups \
  /storage/apps/gitea/data \
  /storage/apps/gitea/postgresql \
  /storage/apps/pocket-id/data \
  /storage/apps/dawarich/backups \
  /storage/apps/dawarich/postgresql \
  /storage/apps/dawarich/public \
  /storage/apps/dawarich/redis \
  /storage/apps/dawarich/shared \
  /storage/apps/dawarich/storage \
  /storage/apps/dawarich/watched \
  /storage/apps/beszel/data \
  /storage/apps/beszel/agent \
  /storage/apps/beszel/socket \
  /storage/apps/traefik/letsencrypt \
  /storage/apps/uptime-kuma/data \
  /storage/apps/restic/cache \
  /storage/apps/restic/restore \
  /storage/media \
  /storage/backups/restic

chmod 0700 \
  /storage/apps/3x-ui \
  /storage/apps/3x-ui/db \
  /storage/apps/3x-ui/log

chmod 0700 \
  /storage/apps/pocket-id \
  /storage/apps/pocket-id/data

if [[ -x /storage/apps/traefik/letsencrypt ]]; then
  if [[ ! -e /storage/apps/traefik/letsencrypt/acme.json ]]; then
    install -m 0600 /dev/null /storage/apps/traefik/letsencrypt/acme.json
  fi
else
  echo 'Пропуск: каталог Traefik ACME недоступен текущему пользователю'
fi

docker network inspect traefiknet >/dev/null 2>&1 || docker network create traefiknet >/dev/null

create_traefik_env
create_pihole_env
create_uptime_kuma_env
create_3x_ui_env
create_nextcloud_env
create_jellyfin_env
create_gitea_env
create_pocket_id_env
create_dawarich_env
create_beszel_env
create_restic_env

chmod 600 \
  "$repo_root/traefik/.env" \
  "$repo_root/pihole/.env" \
  "$repo_root/uptime-kuma/.env" \
  "$repo_root/3x-ui/.env" \
  "$repo_root/nextcloud/.env" \
  "$repo_root/jellyfin/.env" \
  "$repo_root/gitea/.env" \
  "$repo_root/pocket-id/.env" \
  "$repo_root/dawarich/.env" \
  "$repo_root/beszel/.env" \
  "$repo_root/restic/.env"

for service in traefik pihole uptime-kuma 3x-ui nextcloud jellyfin gitea pocket-id dawarich; do
  docker compose --project-directory "$repo_root/$service" config --quiet
done

docker compose \
  --project-directory "$repo_root/beszel" \
  --profile agent \
  config --quiet

docker compose \
  --project-directory "$repo_root/restic" \
  --profile manual \
  config --quiet

echo "Подготовка завершена. Пароли сохранены только в локальных .env сервера."
