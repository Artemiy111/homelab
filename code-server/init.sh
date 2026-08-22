#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0750 \
  "$APPS_STORAGE_PATH"/code-server \
  "$APPS_STORAGE_PATH"/code-server/home \
  "$APPS_STORAGE_PATH"/code-server/workspace

# Публичная конфигурация сервиса — в закоммиченном config.env.

compose_config "$repo_root/code-server"
