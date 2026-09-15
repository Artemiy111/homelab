#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

# VictoriaMetrics работает под user "1000:1000" (uid artlab) — каталог
# создаётся от artlab и доступен ему на запись.
ensure_dirs 0750 "$APPS_STORAGE_PATH"/victoria-metrics/vmdata

compose_config "$repo_root/apps/victoria-metrics"
