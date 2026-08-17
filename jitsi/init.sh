#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

# Configuration input, read by the containers at startup.
ensure_dirs 0750 \
  /storage/apps/jitsi/web \
  /storage/apps/jitsi/prosody/config \
  /storage/apps/jitsi/prosody/prosody-plugins-custom \
  /storage/apps/jitsi/jicofo \
  /storage/apps/jitsi/jvb

# Persistent state and runtime files, writable by the container user (uid 1000).
ensure_dirs 0770 \
  /storage/apps/jitsi/storage \
  /storage/apps/jitsi/storage/prosody \
  /storage/apps/jitsi/storage/web \
  /storage/apps/jitsi/storage/transcripts \
  /storage/apps/jitsi/tmp \
  /storage/apps/jitsi/tmp/web-crontabs \
  /storage/apps/jitsi/tmp/web-load-test

write_env_file "$repo_root/jitsi/.env" <<EOF
JITSI_IMAGE_VERSION=stable-11146-1
JITSI_HOST=meet.$DOMAIN
PUBLIC_URL=https://meet.$DOMAIN
TZ=Asia/Yekaterinburg
RESOLUTION=1080
RESOLUTION_MIN=180
RESOLUTION_WIDTH=1920
RESOLUTION_WIDTH_MIN=320
VIDEOQUALITY_BITRATE_AV1_FULL=2500000
VIDEOQUALITY_BITRATE_H264_FULL=3500000
VIDEOQUALITY_BITRATE_VP8_FULL=3500000
VIDEOQUALITY_BITRATE_VP9_FULL=2500000
JVB_BIND_ADDRESS=192.0.2.10
JVB_ADVERTISE_IPS=192.0.2.10
JVB_PORT=10000
ENABLE_AUTH=1
ENABLE_GUESTS=1
AUTH_TYPE=internal
JICOFO_COMPONENT_SECRET=$(random_secret)
JICOFO_AUTH_PASSWORD=$(random_secret)
JVB_AUTH_PASSWORD=$(random_secret)
EOF

compose_config "$repo_root/jitsi"
