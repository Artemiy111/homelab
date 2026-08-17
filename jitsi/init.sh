#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

# Configuration input, read by the containers at startup.
ensure_dirs 0750 \
  "$APPS_STORAGE_PATH"/jitsi/web \
  "$APPS_STORAGE_PATH"/jitsi/prosody/config \
  "$APPS_STORAGE_PATH"/jitsi/prosody/prosody-plugins-custom \
  "$APPS_STORAGE_PATH"/jitsi/jicofo \
  "$APPS_STORAGE_PATH"/jitsi/jvb

# Persistent state and runtime files, writable by the container user (uid 1000).
ensure_dirs 0770 \
  "$APPS_STORAGE_PATH"/jitsi/storage \
  "$APPS_STORAGE_PATH"/jitsi/storage/prosody \
  "$APPS_STORAGE_PATH"/jitsi/storage/web \
  "$APPS_STORAGE_PATH"/jitsi/storage/transcripts \
  "$APPS_STORAGE_PATH"/jitsi/tmp \
  "$APPS_STORAGE_PATH"/jitsi/tmp/web-crontabs \
  "$APPS_STORAGE_PATH"/jitsi/tmp/web-load-test

write_env_file "$repo_root/jitsi/.env" <<EOF
APPS_STORAGE_PATH=$APPS_STORAGE_PATH
JITSI_IMAGE_VERSION=stable-11146-1
JITSI_HOST=meet.$DOMAIN
PUBLIC_URL=https://meet.$DOMAIN
TZ=$TZ
RESOLUTION=1080
RESOLUTION_MIN=180
RESOLUTION_WIDTH=1920
RESOLUTION_WIDTH_MIN=320
VIDEOQUALITY_BITRATE_AV1_FULL=2500000
VIDEOQUALITY_BITRATE_H264_FULL=3500000
VIDEOQUALITY_BITRATE_VP8_FULL=3500000
VIDEOQUALITY_BITRATE_VP9_FULL=2500000
JVB_BIND_ADDRESS=$SERVER_IP
JVB_ADVERTISE_IPS=$SERVER_IP
JVB_PORT=10000
ENABLE_AUTH=1
ENABLE_GUESTS=1
AUTH_TYPE=internal
JICOFO_COMPONENT_SECRET=$(random_secret)
JICOFO_AUTH_PASSWORD=$(random_secret)
JVB_AUTH_PASSWORD=$(random_secret)
EOF

compose_config "$repo_root/jitsi"
