#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_file="$project_dir/.env"

random_secret() {
  openssl rand -hex 24
}

if [[ -e "$env_file" ]]; then
  echo "Пропуск: $env_file уже существует"
else
  umask 077
  {
    echo 'JITSI_IMAGE_VERSION=stable-10978'
    echo 'JITSI_HOST=meet.example.net'
    echo 'PUBLIC_URL=https://meet.example.net'
    echo 'TZ=Asia/Yekaterinburg'
    echo 'RESOLUTION=1080'
    echo 'RESOLUTION_MIN=180'
    echo 'RESOLUTION_WIDTH=1920'
    echo 'RESOLUTION_WIDTH_MIN=320'
    echo 'VIDEOQUALITY_BITRATE_AV1_FULL=2500000'
    echo 'VIDEOQUALITY_BITRATE_H264_FULL=3500000'
    echo 'VIDEOQUALITY_BITRATE_VP8_FULL=3500000'
    echo 'VIDEOQUALITY_BITRATE_VP9_FULL=2500000'
    echo 'JVB_BIND_ADDRESS=192.0.2.10'
    echo 'JVB_ADVERTISE_IPS=192.0.2.10'
    echo 'JVB_PORT=10000'
    echo 'ENABLE_AUTH=1'
    echo 'ENABLE_GUESTS=1'
    echo 'AUTH_TYPE=internal'
    printf 'JICOFO_COMPONENT_SECRET=%s\n' "$(random_secret)"
    printf 'JICOFO_AUTH_PASSWORD=%s\n' "$(random_secret)"
    printf 'JVB_AUTH_PASSWORD=%s\n' "$(random_secret)"
  } >"$env_file"
fi

chmod 600 "$env_file"

install -d -m 0750 \
  /storage/apps/jitsi/web/crontabs \
  /storage/apps/jitsi/transcripts \
  /storage/apps/jitsi/prosody/config \
  /storage/apps/jitsi/prosody/prosody-plugins-custom \
  /storage/apps/jitsi/jicofo \
  /storage/apps/jitsi/jvb

docker network inspect traefiknet >/dev/null 2>&1 || docker network create traefiknet >/dev/null
docker compose --project-directory "$project_dir" config --quiet

echo "Jitsi подготовлен. Секреты сохранены только в $env_file."
