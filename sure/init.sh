#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

ensure_dirs 0700 \
  "$APPS_STORAGE_PATH/sure/data/app" \
  "$APPS_STORAGE_PATH/sure/data/postgresql" \
  "$APPS_STORAGE_PATH/sure/data/redis" \
  "$APPS_STORAGE_PATH/sure/data/backups"

# Read local-ai API key if available
local_ai_key=""
if [[ -f "$repo_root/local-ai/.env" ]]; then
  local_ai_key="$(grep '^LOCALAI_API_KEY=' "$repo_root/local-ai/.env" 2>/dev/null | cut -d= -f2- || true)"
fi

write_env_file "$repo_root/sure/.env" <<EOF
APPS_STORAGE_PATH=$APPS_STORAGE_PATH
SURE_HOST=sure.$DOMAIN
POSTGRES_DB=sure_production
POSTGRES_USER=sure_user
POSTGRES_PASSWORD=$(random_secret)
SECRET_KEY_BASE=$(openssl rand -hex 64)
OPENAI_ACCESS_TOKEN=${local_ai_key}
OPENAI_MODEL=gpt-4o
OPENAI_URI_BASE=https://localai.example.com/v1
LLM_CONTEXT_WINDOW=8192
OPENAI_REQUEST_TIMEOUT=300
ASSISTANT_MAX_TOOL_CALL_ITERATIONS=2
AI_RESPONSE_TIMEOUT=1200
EOF

compose_config "$repo_root/sure"
