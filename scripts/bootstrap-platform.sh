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
  /storage/apps/pihole/etc-pihole \
  /storage/apps/traefik/letsencrypt \
  /storage/apps/uptime-kuma/data \
  /storage/apps/restic/cache \
  /storage/apps/restic/restore \
  /storage/backups/restic

if [[ ! -e /storage/apps/traefik/letsencrypt/acme.json ]]; then
  install -m 0600 /dev/null /storage/apps/traefik/letsencrypt/acme.json
fi

docker network inspect traefiknet >/dev/null 2>&1 || docker network create traefiknet >/dev/null

create_traefik_env
create_pihole_env
create_uptime_kuma_env
create_restic_env

chmod 600 \
  "$repo_root/traefik/.env" \
  "$repo_root/pihole/.env" \
  "$repo_root/uptime-kuma/.env" \
  "$repo_root/restic/.env"

for service in traefik pihole uptime-kuma; do
  docker compose --project-directory "$repo_root/$service" config --quiet
done

docker compose \
  --project-directory "$repo_root/restic" \
  --profile manual \
  config --quiet

echo "Подготовка завершена. Пароли сохранены только в локальных .env сервера."
