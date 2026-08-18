#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

write_env_file "$repo_root/talk-hpb/.env" <<EOF
TALK_IMAGE_VERSION=20260817_082005
SERVER_IP=$SERVER_IP
NC_DOMAIN=nextcloud.$DOMAIN
TALK_HOST=talk-signaling.$DOMAIN
TURN_DOMAIN=talk-signaling.$DOMAIN
TALK_PORT=3478
TALK_MAX_STREAM_BITRATE=15728640
TALK_MAX_SCREEN_BITRATE=26214400
TURN_SECRET=$(random_secret)
SIGNALING_SECRET=$(random_secret)
INTERNAL_SECRET=$(random_secret)
TZ=$TZ
EOF

compose_config "$repo_root/talk-hpb"
