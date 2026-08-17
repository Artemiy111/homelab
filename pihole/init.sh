#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p /storage/apps/pihole/etc-pihole

write_env_file "$repo_root/pihole/.env" <<EOF
PIHOLE_HOST=pihole.$DOMAIN
PIHOLE_ADMIN_PASSWORD=$(random_secret)
EOF

render_domain_template \
  "$repo_root/pihole/etc-dnsmasq.d/05-homelab.conf.tpl" \
  "$repo_root/pihole/etc-dnsmasq.d/05-homelab.conf"

compose_config "$repo_root/pihole"
