#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p \
  "$APPS_STORAGE_PATH"/beszel/data \
  "$APPS_STORAGE_PATH"/beszel/agent \
  "$APPS_STORAGE_PATH"/beszel/socket

compose_config "$repo_root/apps/beszel" --profile agent
