#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

mkdir -p "$APPS_STORAGE_PATH"/technitium/etc "$APPS_STORAGE_PATH"/technitium/data

write_env_file "$repo_root/technitium/.env" <<EOF
APPS_STORAGE_PATH=$APPS_STORAGE_PATH
SERVER_IP=$SERVER_IP
TZ=$TZ
TECHNITIUM_HOST=dns.$DOMAIN
TECHNITIUM_ADMIN_PASSWORD=$(random_secret)
EOF

compose_config "$repo_root/technitium"

# --- Автоматическая настройка зоны и forwarders ---
# Выполняется только если контейнер запущен и отвечает на API.

technitium_url="http://${SERVER_IP}:5300"

if ! curl -sf --max-time 5 "$technitium_url/" >/dev/null 2>&1; then
  echo "Technitium не отвечает на $technitium_url — пропуск автоматической настройки зоны."
  echo "Запустите контейнер и выполните настройку вручную (см. technitium/README.md)."
  exit 0
fi

source "$repo_root/technitium/.env"

# Токен авторизации (пароль по умолчанию или заданный).
token=$(curl -sf "$technitium_url/api/user/login?user=admin&pass=$TECHNITIUM_ADMIN_PASSWORD" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])" 2>/dev/null || true)

if [[ -z "$token" ]]; then
  # Возможно, пароль уже был изменён; пробуем дефолтный.
  token=$(curl -sf "$technitium_url/api/user/login?user=admin&pass=admin" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])" 2>/dev/null || true)
fi

if [[ -z "$token" ]]; then
  echo "Не удалось получить токен Technitium. Настройте зону вручную (см. technitium/README.md)."
  exit 0
fi

echo "Technitium API доступен, настройка зоны $DOMAIN ..."

# Создать зону (идемпотентно — ошибка «zone already exists» не является фатальной).
curl -sf "$technitium_url/api/zones/create?token=$token&zone=$DOMAIN&type=Primary" >/dev/null 2>&1 \
  && echo "  Зона $DOMAIN создана." \
  || echo "  Зона $DOMAIN уже существует (пропуск)."

# Wildcard A-запись: *.domain → SERVER_IP
wildcard_resp=$(curl -sf "$technitium_url/api/zones/records/add?token=$token&domain=%2A.$DOMAIN&zone=$DOMAIN&type=A&ipAddress=$SERVER_IP&ttl=3600" 2>/dev/null || true)
if echo "$wildcard_resp" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('status')=='ok' else 1)" 2>/dev/null; then
  echo "  Wildcard A-запись *.${DOMAIN} → ${SERVER_IP} добавлена."
else
  echo "  Wildcard A-запись уже существует или произошла ошибка (пропуск)."
fi

# A-запись для DNS-панели: dns.domain → SERVER_IP
dns_resp=$(curl -sf "$technitium_url/api/zones/records/add?token=$token&domain=dns.$DOMAIN&zone=$DOMAIN&type=A&ipAddress=$SERVER_IP&ttl=3600" 2>/dev/null || true)
if echo "$dns_resp" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('status')=='ok' else 1)" 2>/dev/null; then
  echo "  A-запись dns.${DOMAIN} → ${SERVER_IP} добавлена."
else
  echo "  A-запись dns.${DOMAIN} уже существует или произошла ошибка (пропуск)."
fi

# Upstream-резолверы (Cloudflare).
curl -sf "$technitium_url/api/settings/set?token=$token&forwarders=1.1.1.1,1.0.0.1" >/dev/null 2>&1 \
  && echo "  Upstream-резолверы: 1.1.1.1, 1.0.0.1" \
  || echo "  Не удалось задать upstream-резолверы (настройте вручную)."

echo "Настройка Technitium завершена."
