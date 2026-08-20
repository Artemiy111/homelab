# Technitium DNS Server

Technitium — полноценный DNS-сервер с веб-интерфейсом, блокировкой рекламы и
встроенной рекурсией. Заменяет Pi-hole: слушает порт 53 (DNS) и 5380 (веб-
панель, проброшен наружу как 5300). Локальная wildcard-запись разрешает
`example.com` и все его поддомены в `192.0.2.10`.

## Перед запуском

Убедиться, что порт 53 не занят другим сервисом хоста:

```sh
sudo ss -lntup | grep ':53 '
```

Создать файл окружения и постоянные каталоги:

```sh
cp .env.example .env
sudo install -d -m 0750 ${APPS_STORAGE_PATH:-/storage/apps}/technitium/etc
sudo install -d -m 0750 ${APPS_STORAGE_PATH:-/storage/apps}/technitium/data
```

Внешняя сеть `traefiknet` должна уже существовать. Запустить Technitium:

```sh
docker compose up -d
```

Затем в настройках DHCP роутера указать `192.0.2.10` как DNS-сервер. После
изменения настройки обновить DHCP-аренду на клиентах.

## Добавление зоны для homelab

### Через веб-интерфейс

Открыть `http://192.0.2.10:5300/` или `https://dns.example.com/` (после
настройки Traefik). Войти под `admin` (пароль по умолчанию `admin`).

1. Zones → New Zone → Primary → ввести `example.com`.
2. Добавить A-запись: Name `*`, Value `192.0.2.10`, TTL `3600`.

### Через REST API

```sh
# Получить токен
TOKEN=$(curl -s "http://192.0.2.10:5300/api/user/login?user=admin&pass=admin" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

# Создать зону
curl -s "http://192.0.2.10:5300/api/zones/create?token=$TOKEN&zone=example.com&type=Primary"

# Добавить wildcard A-запись
curl -s "http://192.0.2.10:5300/api/zones/records/add?token=$TOKEN&domain=%2A.example.com&zone=example.com&type=A&ipAddress=192.0.2.10&ttl=3600"

# Добавить A-запись для dns поддомена
curl -s "http://192.0.2.10:5300/api/zones/records/add?token=$TOKEN&domain=dns.example.com&zone=example.com&type=A&ipAddress=192.0.2.10&ttl=3600"
```

## Настройка upstream-резолверов

По умолчанию Technitium использует встроенный рекурсивный resolver. Для
перенаправления запросов на Cloudflare:

```sh
curl -s "http://192.0.2.10:5300/api/settings/set?token=$TOKEN&forwarders=1.1.1.1,1.0.0.1"
```

Или через веб-интерфейс: Settings → Resolution → Forwarders → добавить
`1.1.1.1` и `1.0.0.1`.

## Блокировка рекламы

Technitium поддерживает встроенную блокировку. Для включения:

1. Settings → Apps → Enable Blocking App.
2. Добавить источники списков (например, Steven Black's unified hosts).

## Веб-интерфейс

Административная панель доступна по адресу `https://dns.example.com/`
(через Traefik) или напрямую по `http://192.0.2.10:5300/`. По умолчанию
используется self-signed сертификат; для импорта собственного сертификата
перейти в Settings → Certificates.

DNS и веб-интерфейс Technitium нельзя публиковать через интернет-роутер.

Если блокировка и локальные имена должны работать постоянно, не следует
добавлять внешний DNS как второй DNS-сервер DHCP: клиенты не считают второй DNS
строго резервным и могут обращаться к нему напрямую.
