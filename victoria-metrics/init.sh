#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

# Данные TSDB пишет root (образ VictoriaMetrics), каталог достаточно 0755.
ensure_dirs 0755 "$APPS_STORAGE_PATH"/victoria-metrics/vmdata
# Grafana работает под user "1000:1000" — каталог создаётся от artlab (uid 1000).
ensure_dirs 0750 "$APPS_STORAGE_PATH"/victoria-metrics/grafana

# Конфигурация приходит через окружение: bootstrap подмешивает config.env
# и расшифровывает secrets.enc.env (sops exec-env). Plaintext .env не создаётся.

compose_config "$repo_root/victoria-metrics"
