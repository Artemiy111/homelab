# Technitium DNS Server: эксплуатация

## Перед запуском

Убедиться, что порт 53 не занят другим сервисом хоста:

```sh
sudo ss -lntup | grep ':53 '
```

Затем в настройках DHCP роутера указать `${HOST_IP}` как DNS-сервер. После
изменения настройки обновить DHCP-аренду на клиентах.

## Добавление зоны для homelab

### Через веб-интерфейс

Открыть `https://dns.${DOMAIN}/` (через Traefik). Войти под `admin`; пароль
берётся из Vault (`kv/technitium/secret`, `TECHNITIUM_ADMIN_PASSWORD`).

1. Zones → New Zone → Primary → ввести `${DOMAIN}`.
2. Добавить A-запись: Name `*`, Value `${HOST_IP}`, TTL `3600`.

### Через REST API

```sh
# Получить токен
TOKEN=$(curl -s "http://${HOST_IP}:5380/api/user/login?user=admin&pass=admin" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

# Создать зону
curl -s "http://${HOST_IP}:5380/api/zones/create?token=$TOKEN&zone=${DOMAIN}&type=Primary"

# Добавить wildcard A-запись
curl -s "http://${HOST_IP}:5380/api/zones/records/add?token=$TOKEN&domain=%2A.${DOMAIN}&zone=${DOMAIN}&type=A&ipAddress=${HOST_IP}&ttl=3600"

# Добавить A-запись для dns поддомена
curl -s "http://${HOST_IP}:5380/api/zones/records/add?token=$TOKEN&domain=dns.${DOMAIN}&zone=${DOMAIN}&type=A&ipAddress=${HOST_IP}&ttl=3600"
```

## Настройка upstream-резолверов

Актуальная рабочая схема — **DoH Cloudflare с закреплённым бутстрапом** через
локальную зону (почему так — см. «Хроника» в `README.md`):

```sh
# Форвардер DoH
curl -s "http://${HOST_IP}:5380/api/settings/set?token=$TOKEN&forwarders=https%3A%2F%2Fcloudflare-dns.com%2Fdns-query&forwarderProtocol=Https"

# Локальная зона: закрепляет имя форвардера на незаблокированные провайдером IP.
# Канонические IP cloudflare-dns.com из DNS-раунд-робина (104.16.248.249/104.16.249.249)
# у провайдера блокируются по DPI; соседние anycast работают.
curl -s "http://${HOST_IP}:5380/api/zones/create?token=$TOKEN&zone=cloudflare-dns.com&type=Primary"
curl -s "http://${HOST_IP}:5380/api/zones/records/add?token=$TOKEN&domain=cloudflare-dns.com&zone=cloudflare-dns.com&type=A&ipAddress=104.16.123.96&ttl=3600"
curl -s "http://${HOST_IP}:5380/api/zones/records/add?token=$TOKEN&domain=cloudflare-dns.com&zone=cloudflare-dns.com&type=A&ipAddress=104.16.132.229&ttl=3600"
```

После изменения форвардеров нужно перезапустить Technitium: подключение к
форвардеру кэшируется вместе с его IP.

Проверка здоровья схемы:

```sh
dig @${HOST_IP} cloudflare-dns.com +short   # должны вернуться закреплённые IP
dig @${HOST_IP} google.com +short           # внешние имена
```

Проверка, что узел ходит в Technitium не только явным `dig @${HOST_IP}`, но и
своим резолвером (иначе pull образов держится на кэше systemd-resolved, а новое
имя в зоне не разрешится):

```sh
resolvectl query --cache=no probe-$(date +%s).${DOMAIN}
```

Ожидается `${HOST_IP}`. Резолверы узла задаёт Ansible-роль `resolver`; если
запрос уходит в роутер, роль не применена.

## Обновление

`strategy: Recreate`: старый под удаляется до того, как скачается новый образ, а
образ тянется с `registry-1.docker.io` — имя резолвит сам Technitium. Если
резолвер узла зависит от него же, новый под не стартует, и вместе с ним
пропадает DNS всей сети (docs/incidents/0012). Поэтому образ оказывается на
узле **до** merge:

1. Скачать образ подом, который использует тот же kubelet и ничего не делает:

   ```sh
   kubectl run preload --image=technitium/dns-server:<версия> --restart=Never -- sleep 3600
   kubectl wait --for=condition=Ready pod/preload --timeout=5m
   kubectl delete pod preload
   ```

2. Убедиться, что узел резолвит внешние имена без кластера:

   ```sh
   dig +short registry-1.docker.io
   ```

3. Смержить PR и дождаться роллаута:

   ```sh
   kubectl -n technitium rollout status deploy/technitium
   ```

4. Проверить, что DNS сети вернулся: `dig @${HOST_IP} google.com +short`.

## Сброс пароля администратора

ENV `DNS_ADMIN_PASSWORD` применяется только при первичной инициализации.
Сброс существующего пароля: удалить `auth.config` в каталоге данных сервиса
(`/storage/apps/technitium/etc/auth.config`) — учётка пересоздастся как
`admin/admin`.

Затем сменить пароль через API (`api/user/changePassword` с параметрами
`token`, `pass` — старый, `newPass` — новый) и записать новый в Vault
(`kv/technitium/secret`).

## Блокировка рекламы

Technitium поддерживает встроенную блокировку. Для включения:

1. Settings → Apps → Enable Blocking App.
2. Добавить источники списков (например, Steven Black's unified hosts).
