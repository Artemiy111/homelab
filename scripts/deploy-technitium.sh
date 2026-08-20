#!/usr/bin/env bash
# =============================================================================
# Деплой Technitium DNS Server на сервере homelab.
#
# Этот скрипт выполняется ОДИН РАЗ от имени artlab (или root для resolvectl).
# Он документирует все изменения, внесённые на сервере при замене Pi-hole
# на Technitium DNS Server.
#
# Изменения:
#   1. Git: переключение на ветку t3code/replace-pihole-technitium
#   2. Docker: остановка и удаление контейнера pihole
#   3. Docker: pull и запуск контейнера technitium
#   4. Technitium API: создание зоны example.com, wildcard A-запись,
#      A-запись dns.example.com, upstream-резолверы (Cloudflare)
#   5. DNS сервера: переключение wlp3s0 на 192.0.2.10 (ТРЕБУЕТ root)
#   6. DHCP роутера: вернуть DNS на 192.0.2.10 (вручную)
#
# Запуск:
#   sudo -u artlab bash scripts/deploy-technitium.sh
#   (пункт 5 потребует пароля root)
# =============================================================================

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

echo "============================================="
echo "  Деплой Technitium DNS Server"
echo "============================================="
echo

# ── 1. Git ──────────────────────────────────────────────────────────────────

echo "[1/6] Git: переключение на ветку с Technitium ..."
cd "$repo_root"
current_branch=$(git branch --show-current)
if [[ "$current_branch" != "t3code/replace-pihole-technitium" ]]; then
  git fetch origin t3code/replace-pihole-technitium
  git checkout t3code/replace-pihole-technitium
fi
git pull --ff-only origin t3code/replace-pihole-technitium
echo "  Ветка: $(git branch --show-current), коммит: $(git log -1 --oneline)"
echo

# ── 2. Остановка Pi-hole ───────────────────────────────────────────────────

echo "[2/6] Остановка Pi-hole ..."
if docker ps --format '{{.Names}}' | grep -q '^pihole$'; then
  docker stop pihole && docker rm pihole
  echo "  Контейнер pihole остановлен и удалён."
else
  echo "  Контейнер pihole не найден (уже удалён)."
fi
echo

# ── 3. Запуск Technitium ───────────────────────────────────────────────────

echo "[3/6] Запуск Technitium DNS Server ..."
cd "$repo_root/technitium"
bash init.sh
docker compose pull
docker compose up -d
echo "  Ожидание健康check (до 60 сек) ..."
timeout=60
until docker inspect --format '{{.State.Health.Status}}' technitium 2>/dev/null | grep -q healthy; do
  sleep 5
  timeout=$((timeout - 5))
  if [[ $timeout -le 0 ]]; then
    echo "  ОШИБКА: Technitium не стал healthy за 60 сек."
    docker logs technitium --tail 20
    exit 1
  fi
done
echo "  Technitium: $(docker ps --filter name=technitium --format '{{.Status}}')"
echo

# ── 4. API: зона и записи ──────────────────────────────────────────────────

echo "[4/6] Настройка зоны через API ..."
technitium_url="http://${SERVER_IP}:5300"

token=$(curl -sf "$technitium_url/api/user/login?user=admin&pass=admin" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])" 2>/dev/null || true)

if [[ -z "$token" ]]; then
  echo "  ОШИБКА: не удалось получить токен. Настройте зону вручную."
  exit 1
fi

# Зона
curl -sf "$technitium_url/api/zones/create?token=$token&zone=$DOMAIN&type=Primary" >/dev/null 2>&1 \
  && echo "  Зона $DOMAIN создана." \
  || echo "  Зона $DOMAIN уже существует."

# Wildcard A
curl -sf "$technitium_url/api/zones/records/add?token=$token&domain=%2A.$DOMAIN&zone=$DOMAIN&type=A&ipAddress=$SERVER_IP&ttl=3600" >/dev/null 2>&1 \
  && echo "  *.${DOMAIN} → ${SERVER_IP}" \
  || echo "  Wildcard уже существует."

# dns A
curl -sf "$technitium_url/api/zones/records/add?token=$token&domain=dns.$DOMAIN&zone=$DOMAIN&type=A&ipAddress=$SERVER_IP&ttl=3600" >/dev/null 2>&1 \
  && echo "  dns.${DOMAIN} → ${SERVER_IP}" \
  || echo "  dns-запись уже существует."

# Forwarders
curl -sf "$technitium_url/api/settings/set?token=$token&forwarders=1.1.1.1,1.0.0.1" >/dev/null 2>&1 \
  && echo "  Forwarders: 1.1.1.1, 1.0.0.1" \
  || echo "  ОШИБКА: не удалось задать forwarders."
echo

# ── 5. DNS сервера (root) ─────────────────────────────────────────────────

echo "[5/6] Переключение DNS сервера на Technitium (root) ..."
echo "  Текущий DNS для wlp3s0:"
resolvectl status wlp3s0 | grep 'DNS Servers:' || true
echo
echo "  Нужно выполнить (требует root):"
echo "    sudo resolvectl dns wlp3s0 $SERVER_IP"
echo "    sudo resolvectl domain wlp3s0 $DOMAIN"
echo
read -rp "  Выполнить сейчас? (y/N) " answer
if [[ "$answer" =~ ^[yY]$ ]]; then
  sudo resolvectl dns wlp3s0 "$SERVER_IP"
  sudo resolvectl domain wlp3s0 "$DOMAIN"
  echo "  DNS сервера переключён на $SERVER_IP."
else
  echo "  Пропущено. Выполните вручную:"
  echo "    sudo resolvectl dns wlp3s0 $SERVER_IP"
  echo "    sudo resolvectl domain wlp3s0 $DOMAIN"
fi
echo

# ── 6. DHCP роутера ────────────────────────────────────────────────────────

echo "[6/6] DHCP роутер ..."
echo "  В настройках DHCP роутера вернуть DNS-сервер на $SERVER_IP."
echo "  (Вручную через веб-интерфейс роутера.)"
echo

# ── Проверка ────────────────────────────────────────────────────────────────

echo "============================================="
echo "  Проверка"
echo "============================================="
echo

echo "DNS: локальная зона"
dig +short @$SERVER_IP uptime.$DOMAIN A
dig +short @$SERVER_IP dns.$DOMAIN A
dig +short @$SERVER_IP meet.$DOMAIN A

echo
echo "DNS: внешний форвардинг"
dig +short @$SERVER_IP google.com A | head -1

echo
echo "Веб-панель (HTTP)"
curl -s -o /dev/null -w "  http://${SERVER_IP}:5300/ → %{http_code}" "http://${SERVER_IP}:5300/"
echo

echo
echo "Контейнер"
docker ps --filter name=technitium --format "  {{.Names}}: {{.Status}}"

echo
echo "============================================="
echo "  Деплой завершён."
echo "============================================="
