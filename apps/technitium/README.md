# Technitium DNS Server

Technitium — полноценный DNS-сервер с веб-интерфейсом, блокировкой рекламы и
встроенной рекурсией. Заменяет Pi-hole: слушает порт 53 (DNS). Веб-панель
доступна через Traefik по адресу `https://dns.${DOMAIN}/`. Локальная
wildcard-запись разрешает `${DOMAIN}` и все его поддомены в `${HOST_IP}`.

## Перед запуском

Разворачивается манифестами в `apps/technitium/k8s/`.

Убедиться, что порт 53 не занят другим сервисом хоста:

```sh
sudo ss -lntup | grep ':53 '
```

Затем в настройках DHCP роутера указать `${HOST_IP}` как DNS-сервер. После
изменения настройки обновить DHCP-аренду на клиентах.

## Добавление зоны для homelab

### Через веб-интерфейс

Открыть `https://dns.${DOMAIN}/` (через Traefik). Войти под `admin`; пароль
хранится в `apps/technitium/secrets.enc.env` (`TECHNITIUM_ADMIN_PASSWORD`).

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
локальную зону (почему так — см. «Хроника отладки» ниже):

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

## DNS-петля через роутер (инцидент 2026-08-21)

Внешние имена отдавали `SERVFAIL` (`Waiting for resolver` в логе), внутренняя
зона работала; пользователи не замечали проблему, пока DNS перехватывал
Tailscale. Корень: на Keenetic был включён глобальный перехват транзитного DNS
(`dns-proxy intercept enable`) — исходящие запросы Technitium к внешним
форвардерам заворачивались обратно в него же, петля → таймауты. Все
«блокировки провайдера» при диагностике были симптомами петли; реально
блокируются только DoT :853 (DPI режет TLS после TCP-connect) и часть IP
Cloudflare (`104.16.248.249`/`104.16.249.249`; соседние anycast работают).

Итоговая схема и условия работоспособности:

```
клиент → Keenetic (system profile → ${HOST_IP}) → Technitium → DoH Cloudflare (закреплённые IP)
```

1. На Keenetic транзитные запросы **разрешены**
   (`no dns-proxy intercept enable`, затем `system configuration save`) —
   иначе петля с центральным резолвером в LAN.
2. Локальная зона `cloudflare-dns.com` закрепляет бутстрап на незаблокированные IP.
3. Клиенты с жёстко прописанным внешним DNS обходят Technitium — осознанный
   trade-off.

### Сброс пароля администратора

ENV `DNS_ADMIN_PASSWORD` применяется только при первичной инициализации.
Сброс существующего пароля: удалить `auth.config` в каталоге данных сервиса
(`/storage/apps/technitium/etc/auth.config`) — учётка пересоздастся как
`admin/admin`.

Затем сменить пароль через API (`api/user/changePassword` с параметрами
`token`, `pass` — старый, `newPass` — новый) и записать его в секреты сервиса
(`secrets.enc.env`).

## Блокировка рекламы

Technitium поддерживает встроенную блокировку. Для включения:

1. Settings → Apps → Enable Blocking App.
2. Добавить источники списков (например, Steven Black's unified hosts).

## Веб-интерфейс

Административная панель доступна по адресу `https://dns.${DOMAIN}/`
(через Traefik). По умолчанию используется self-signed сертификат; для импорта
собственного сертификата перейти в Settings → Certificates.

DNS и веб-интерфейс Technitium нельзя публиковать через интернет-роутер.

Если блокировка и локальные имена должны работать постоянно, не следует
добавлять внешний DNS как второй DNS-сервер DHCP: клиенты не считают второй DNS
строго резервным и могут обращаться к нему напрямую.
