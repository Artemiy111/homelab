#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 "$APPS_STORAGE_PATH/vault/data"

# Публичная конфигурация сервиса — в закоммиченном config.env.

compose_config "$repo_root/apps/vault"
