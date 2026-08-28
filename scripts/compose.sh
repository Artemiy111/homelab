#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Использование: $0 <каталог-сервиса> <аргументы compose...>" >&2
  exit 1
fi

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
service="$1"
shift


source "$repo_root/scripts/lib/common.sh"
service_compose "$service" "$@"
