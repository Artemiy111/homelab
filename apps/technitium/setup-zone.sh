#!/usr/bin/env bash

# Одноразовая настройка зоны и forwarders в Technitium через REST API.
# Требует запущенный контейнер. Не вызывается bootstrap-platform.sh.

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

# shellcheck disable=SC1091
source "$repo_root/apps/technitium/.env"

# IP-адрес контейнера в Docker-сети (доступен без проброса портов).
container_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' technitium 2>/dev/null || true)
if [[ -z "$container_ip" ]]; then
  echo "Контейнер technitium не запущен." >&2
  exit 1
fi

api="http://${container_ip}:5380/api"

# Авторизация: пробуем заданный пароль, затем дефолтный.
token=$(curl -sf "${api}/user/login?user=admin&pass=${TECHNITIUM_ADMIN_PASSWORD}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])" 2>/dev/null || true)

if [[ -z "$token" ]]; then
  token=$(curl -sf "${api}/user/login?user=admin&pass=admin" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])" 2>/dev/null || true)
fi

if [[ -z "$token" ]]; then
  echo "Не удалось получить токен. Настройте зону вручную (см. technitium/README.md)." >&2
  exit 1
fi

echo "Technitium API доступен, настройка зоны $DOMAIN ..."

# Зона (идемпотентно).
curl -sf "${api}/zones/create?token=${token}&zone=${DOMAIN}&type=Primary" >/dev/null 2>&1 \
  && echo "  Зона $DOMAIN создана." \
  || echo "  Зона $DOMAIN уже существует (пропуск)."

# Wildcard A-запись: *.domain → SERVER_IP
wildcard_resp=$(curl -sf "${api}/zones/records/add?token=${token}&domain=%2A.${DOMAIN}&zone=${DOMAIN}&type=A&ipAddress=${SERVER_IP}&ttl=3600" 2>/dev/null || true)
if echo "$wildcard_resp" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('status')=='ok' else 1)" 2>/dev/null; then
  echo "  Wildcard A-запись *.${DOMAIN} → ${SERVER_IP} добавлена."
else
  echo "  Wildcard A-запись уже существует или произошла ошибка (пропуск)."
fi

# A-запись для DNS-панели: dns.domain → SERVER_IP
dns_resp=$(curl -sf "${api}/zones/records/add?token=${token}&domain=dns.${DOMAIN}&zone=${DOMAIN}&type=A&ipAddress=${SERVER_IP}&ttl=3600" 2>/dev/null || true)
if echo "$dns_resp" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('status')=='ok' else 1)" 2>/dev/null; then
  echo "  A-запись dns.${DOMAIN} → ${SERVER_IP} добавлена."
else
  echo "  A-запись dns.${DOMAIN} уже существует или произошла ошибка (пропуск)."
fi

# Upstream-резолверы (Cloudflare).
curl -sf "${api}/settings/set?token=${token}&forwarders=1.1.1.1,1.0.0.1" >/dev/null 2>&1 \
  && echo "  Upstream-резолверы: 1.1.1.1, 1.0.0.1" \
  || echo "  Не удалось задать upstream-резолверы (настройте вручную)."

echo "Настройка Technitium завершена."
