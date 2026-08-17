#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p /storage/apps/pihole/etc-pihole

write_env_file "$repo_root/pihole/.env" <<EOF
SERVER_IP=$SERVER_IP
PIHOLE_HOST=pihole.$DOMAIN
PIHOLE_ADMIN_PASSWORD=$(random_secret)
EOF

render_template \
  "$repo_root/pihole/etc-dnsmasq.d/05-homelab.conf.tpl" \
  "$repo_root/pihole/etc-dnsmasq.d/05-homelab.conf" \
  '\$DOMAIN \$SERVER_IP'

compose_config "$repo_root/pihole"
