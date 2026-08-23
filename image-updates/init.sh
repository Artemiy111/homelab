#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p "$APPS_STORAGE_PATH"/wud/store

# Cup для Docker Hub отправляет `Authorization: Basic base64(логин:токен)`
# (как в ~/.docker/config.json). Креды приходят из окружения (config.env +
# secrets.enc.env), готовая строка подставляется в cup.json через render_template.
# Пока токен не задан, блок registries не рендерится — Cup работает анонимно
# (лимит 100 pulls/6h).

CUP_DOCKERHUB_REGISTRIES=""
if [[ -n "$CUP_DOCKERHUB_TOKEN" ]]; then
  basic_auth="$(printf '%s:%s' "$CUP_DOCKERHUB_USERNAME" "$CUP_DOCKERHUB_TOKEN" | base64 -w0)"
  CUP_DOCKERHUB_REGISTRIES=",\"registries\":{\"registry-1.docker.io\":{\"authentication\":\"$basic_auth\"}}"
fi

# vals flatten читает переменные из окружения процесса, поэтому экспорт.
export CUP_DOCKERHUB_REGISTRIES
render_template \
  "$repo_root/image-updates/cup.tpl.json" \
  "$repo_root/image-updates/cup.json"

compose_config "$repo_root/image-updates"
