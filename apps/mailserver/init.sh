#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 \
  "$APPS_STORAGE_PATH"/mailserver/etc \
  "$APPS_STORAGE_PATH"/mailserver/data
ensure_dirs 0750 "$APPS_STORAGE_PATH"/mailserver/mail

# Basic auth для Prometheus-метрик (включается в WebUI: Settings →
# Telemetry → Metrics): креды приходят из окружения (STALWART_METRICS_*
# из secrets.enc.env), в контейнер передаются через environment (compose.yaml).

compose_config "$repo_root/apps/mailserver"
