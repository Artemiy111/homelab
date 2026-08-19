# Technitium DNS Server

Technitium — полноценный DNS-сервер с веб-интерфейсом, блокировкой рекламы и
встроенной рекурсией. Заменяет Pi-hole: слушает порт 53 (DNS) и 5300 (веб-
интерфейс). Локальная wildcard-запись разрешает `example.com` и все его
поддомены в `192.0.2.10`.

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

После первого запуска через веб-интерфейс (`https://dns.example.com/`)
добавить Primary Zone:

1. Войти под `admin` с паролем из `.env`.
2. Zones → New Zone → Primary → ввести `example.com`.
3. Добавить A-запись: Name `*`, Value `192.0.2.10`, TTL `3600`.

Альтернативно — через REST API:

```sh
curl -s "https://dns.example.com/api/zones/create?token=$TOKEN&zone=example.com&type=Primary"
curl -s "https://dns.example.com/api/zones/add?token=$TOKEN&domain=*.example.com&zone=example.com&type=A&ipAddress=192.0.2.10&ttl=3600"
```

## Настройка upstream-резолверов

По умолчанию Technitium использует встроенный рекурсивный resolver. Для
перенаправления запросов на Cloudflare (как раньше через Pi-hole):

Settings → Resolution → Forwarders → добавить `1.1.1.1` и `1.0.0.1`.

## Блокировка рекламы

Technitium поддерживает встроенную блокировку. Для включения:

1. Settings → Apps → Enable Blocking App.
2. Добавить источники списков (например, Steven Black's unified hosts).

## Веб-интерфейс

Административная панель доступна по адресу `https://dns.example.com/`.
По умолчанию используется self-signed сертификат; для импорта собственного
сертификата перейти в Settings → Certificates.

DNS и веб-интерфейс Technitium нельзя публиковать через интернет-роутер.

Если блокировка и локальные имена должны работать постоянно, не следует
добавлять внешний DNS как второй DNS-сервер DHCP: клиенты не считают второй DNS
строго резервным и могут обращаться к нему напрямую.
