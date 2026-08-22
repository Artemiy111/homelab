#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 \
  "$APPS_STORAGE_PATH"/mailserver/etc \
  "$APPS_STORAGE_PATH"/mailserver/data
ensure_dirs 0750 "$APPS_STORAGE_PATH"/mailserver/mail

# Basic auth для Prometheus-метрик (включается в WebUI: Settings →
# Telemetry → Metrics); пароль генерируется однократно и хранится в .env.
upsert_env "$repo_root/mailserver/.env" STALWART_METRICS_USERNAME "netdata"
ensure_secret "$repo_root/mailserver/.env" STALWART_METRICS_PASSWORD >/dev/null

compose_config "$repo_root/mailserver"
