#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 \
  "$APPS_STORAGE_PATH"/mailserver/etc \
  "$APPS_STORAGE_PATH"/mailserver/data
ensure_dirs 0750 "$APPS_STORAGE_PATH"/mailserver/mail

# Basic auth для Prometheus-метрик (включается в WebUI: Settings →
# Telemetry → Metrics). Пароль генерируется однократно и хранится в .env;
# в контейнер передаётся через environment (см. compose.yaml), а в WebUI
# указывается вариант Secret → Environment Variable с именем переменной.
ensure_dirs 0700 "$APPS_STORAGE_PATH"/mailserver/etc \
  "$APPS_STORAGE_PATH"/mailserver/data
upsert_env "$repo_root/mailserver/.env" STALWART_METRICS_USERNAME "metrics"
ensure_secret "$repo_root/mailserver/.env" STALWART_METRICS_PASSWORD >/dev/null

compose_config "$repo_root/mailserver"
