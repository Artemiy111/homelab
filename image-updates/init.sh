#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p /storage/apps/wud/store

write_env_file "$repo_root/image-updates/.env" <<EOF
TZ=$TZ
WUD_HOST=wud.$DOMAIN
CUP_HOST=cup.$DOMAIN
# Docker Hub credentials для Cup (PAT с правами read-only). Хранятся только в
# .env, в Git не попадают. Для свежих установок заполните после bootstrap:
#   CUP_DOCKERHUB_USERNAME=<логин Docker Hub>
#   CUP_DOCKERHUB_TOKEN=<Personal Access Token>
CUP_DOCKERHUB_USERNAME=
CUP_DOCKERHUB_TOKEN=
EOF

# Cup для Docker Hub отправляет `Authorization: Basic base64(логин:токен)`
# (как в ~/.docker/config.json). Собираем готовую строку из .env и подставляем
# в cup.json через render_template. Пока токен не задан, блок registries не
# рендерится — Cup работает анонимно (лимит 100 pulls/6h).
CUP_DOCKERHUB_USERNAME="$(sed -n 's/^CUP_DOCKERHUB_USERNAME=//p' "$repo_root/image-updates/.env")"
CUP_DOCKERHUB_TOKEN="$(sed -n 's/^CUP_DOCKERHUB_TOKEN=//p' "$repo_root/image-updates/.env")"

CUP_DOCKERHUB_REGISTRIES=""
if [[ -n "$CUP_DOCKERHUB_TOKEN" ]]; then
  basic_auth="$(printf '%s:%s' "$CUP_DOCKERHUB_USERNAME" "$CUP_DOCKERHUB_TOKEN" | base64 -w0)"
  CUP_DOCKERHUB_REGISTRIES=",\"registries\":{\"registry-1.docker.io\":{\"authentication\":\"$basic_auth\"}}"
fi

CUP_DOCKERHUB_REGISTRIES="$CUP_DOCKERHUB_REGISTRIES" render_template \
  "$repo_root/image-updates/cup.json.tpl" \
  "$repo_root/image-updates/cup.json" \
  '\$CUP_DOCKERHUB_REGISTRIES'

compose_config "$repo_root/image-updates"
