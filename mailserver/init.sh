#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 \
  "$APPS_STORAGE_PATH"/mailserver/etc \
  "$APPS_STORAGE_PATH"/mailserver/data
ensure_dirs 0750 "$APPS_STORAGE_PATH"/mailserver/mail

compose_config "$repo_root/mailserver"
