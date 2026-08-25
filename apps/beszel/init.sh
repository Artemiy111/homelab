#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p \
  "$APPS_STORAGE_PATH"/beszel/data \
  "$APPS_STORAGE_PATH"/beszel/agent \
  "$APPS_STORAGE_PATH"/beszel/socket


# Конфигурация и секреты приходят через окружение: bootstrap подмешивает
# config.env и расшифровывает secrets.enc.env (sops exec-env). Plaintext .env
# не создаётся.

compose_config "$repo_root/apps/beszel" --profile agent
