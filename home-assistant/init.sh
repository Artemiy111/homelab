#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p "$APPS_STORAGE_PATH"/home-assistant

# Публичная конфигурация сервиса — в закоммиченном config.env.

compose_config "$repo_root/home-assistant"
