#!/usr/bin/env bash

set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Запустите скрипт через sudo: sudo bash tailscale/setup.sh" >&2
  exit 1
fi

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

curl --fail --silent --show-error --location \
  https://pkgs.tailscale.com/stable/fedora/tailscale.repo \
  --output /etc/yum.repos.d/tailscale.repo

dnf install --assumeyes tailscale
systemctl enable --now tailscaled

install \
  --owner=root \
  --group=root \
  --mode=0644 \
  "$repo_root/apps/tailscale/99-tailscale.conf" \
  /etc/sysctl.d/99-tailscale.conf
sysctl --load /etc/sysctl.d/99-tailscale.conf

tailscale up \
  --hostname=homelab \
  --advertise-routes=192.0.2.10/24

echo
echo "Tailscale подключён. Одобрите маршрут 192.0.2.10/24 в admin console."
