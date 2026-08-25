#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

# Configuration input, read by the containers at startup.
ensure_dirs 0750 \
  "$APPS_STORAGE_PATH"/jitsi/web \
  "$APPS_STORAGE_PATH"/jitsi/prosody/config \
  "$APPS_STORAGE_PATH"/jitsi/prosody/prosody-plugins-custom \
  "$APPS_STORAGE_PATH"/jitsi/jicofo \
  "$APPS_STORAGE_PATH"/jitsi/jvb

# Persistent state and runtime files, writable by the container user (uid 1000).
ensure_dirs 0770 \
  "$APPS_STORAGE_PATH"/jitsi/storage \
  "$APPS_STORAGE_PATH"/jitsi/storage/prosody \
  "$APPS_STORAGE_PATH"/jitsi/storage/web \
  "$APPS_STORAGE_PATH"/jitsi/storage/transcripts \
  "$APPS_STORAGE_PATH"/jitsi/tmp \
  "$APPS_STORAGE_PATH"/jitsi/tmp/web-crontabs \
  "$APPS_STORAGE_PATH"/jitsi/tmp/web-load-test

compose_config "$repo_root/apps/jitsi"
