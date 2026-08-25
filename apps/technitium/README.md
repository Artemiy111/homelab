# Technitium DNS Server

Technitium — полноценный DNS-сервер с веб-интерфейсом, блокировкой рекламы и
встроенной рекурсией. Заменяет Pi-hole: слушает порт 53 (DNS). Веб-панель
доступна через Traefik по адресу `https://dns.${DOMAIN}/`. Локальная
wildcard-запись разрешает `${DOMAIN}` и все его поддомены в `${SERVER_IP}`.

## Перед запуском

Убедиться, что порт 53 не занят другим сервисом хоста:

```sh
sudo ss -lntup | grep ':53 '
```

Подготовить каталоги и `.env`:

Внешняя сеть `traefiknet` должна уже существовать.
```sh
bash scripts/bootstrap-platform.sh technitium
```

Затем в настройках DHCP роутера указать `${SERVER_IP}` как DNS-сервер. После
изменения настройки обновить DHCP-аренду на клиентах.

## Добавление зоны для homelab

### Автоматически (setup-zone.sh)

Скрипт находит контейнер в Docker-сети и настраивает зону через API:

```sh
./technitium/setup-zone.sh
```

### Через веб-интерфейс

Открыть `https://dns.${DOMAIN}/` (через Traefik). Войти под `admin`; пароль
хранится в `apps/technitium/secrets.enc.env` (`TECHNITIUM_ADMIN_PASSWORD`).

1. Zones → New Zone → Primary → ввести `${DOMAIN}`.
2. Добавить A-запись: Name `*`, Value `${SERVER_IP}`, TTL `3600`.

### Через REST API

```sh
# Получить токен
TOKEN=$(curl -s "http://${SERVER_IP}:5380/api/user/login?user=admin&pass=admin" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

# Создать зону
curl -s "http://${SERVER_IP}:5380/api/zones/create?token=$TOKEN&zone=${DOMAIN}&type=Primary"

# Добавить wildcard A-запись
curl -s "http://${SERVER_IP}:5380/api/zones/records/add?token=$TOKEN&domain=%2A.${DOMAIN}&zone=${DOMAIN}&type=A&ipAddress=${SERVER_IP}&ttl=3600"

# Добавить A-запись для dns поддомена
curl -s "http://${SERVER_IP}:5380/api/zones/records/add?token=$TOKEN&domain=dns.${DOMAIN}&zone=${DOMAIN}&type=A&ipAddress=${SERVER_IP}&ttl=3600"
```

## Настройка upstream-резолверов

Актуальная рабочая схема — **DoH Cloudflare с закреплённым бутстрапом** через
локальную зону (почему так — см. «Хроника отладки» ниже):

```sh
# Форвардер DoH
curl -s "http://${SERVER_IP}:5380/api/settings/set?token=$TOKEN&forwarders=https%3A%2F%2Fcloudflare-dns.com%2Fdns-query&forwarderProtocol=Https"

# Локальная зона: закрепляет имя форвардера на незаблокированные провайдером IP.
# Канонические IP cloudflare-dns.com из DNS-раунд-робина (104.16.248.249/104.16.249.249)
# у провайдера блокируются по DPI; соседние anycast работают.
curl -s "http://${SERVER_IP}:5380/api/zones/create?token=$TOKEN&zone=cloudflare-dns.com&type=Primary"
curl -s "http://${SERVER_IP}:5380/api/zones/records/add?token=$TOKEN&domain=cloudflare-dns.com&zone=cloudflare-dns.com&type=A&ipAddress=104.16.123.96&ttl=3600"
curl -s "http://${SERVER_IP}:5380/api/zones/records/add?token=$TOKEN&domain=cloudflare-dns.com&zone=cloudflare-dns.com&type=A&ipAddress=104.16.132.229&ttl=3600"
```

После изменения форвардеров перезапустить контейнер (`docker restart
technitium`): подключение к форвардеру кэшируется вместе с его IP.

Проверка здоровья схемы:

```sh
dig @${SERVER_IP} cloudflare-dns.com +short   # должны вернуться закреплённые IP
dig @${SERVER_IP} google.com +short           # внешние имена
```

## Хроника отладки (2026-08-21)

### Симптом

Внутренняя зона `${DOMAIN}` резолвилась, все внешние имена — `SERVFAIL`
(в логе Technitium: `Waiting for resolver`). Пользователи не замечали проблему,
пока работал Tailscale (перехватывал DNS) или прокси-клиенты с Fake-IP.

### Корень проблемы

На Keenetic был включён глобальный перехват транзитных DNS-запросов
(`dns-proxy intercept enable` в CLI). Technitium — сам LAN-хост, поэтому его
исходящие запросы к внешним форвардерам на порт 53 перехватывались роутером и
заворачивались обратно в системный профиль, то есть снова в Technitium.
Бесконечная петля → таймауты на всё внешнее.

Все «блокировки провайдером» при диагностике оказались симптомами этой петли.
Реальные блокировки у провайдера обнаружились только две:

- **DoT (порт 853)**: TCP-соединение открывается, TLS-рукопожатие убивается DPI;
- **часть IP Cloudflare**: канонические `104.16.248.249`/`104.16.249.249`
  блокируются, соседние anycast `104.16.123.96`/`104.16.132.229` работают.

### Опробованные методы

| # | Метод | Результат |
|---|-------|-----------|
| 1 | Профиль фильтрации Keenetic (`dns-proxy filter profile DnsProfile0` + привязка к Home) | Профиль не подхватывался живым ndns; от отказались, конфиг удалён |
| 2 | Системный профиль Keenetic → `192.0.2.10` | Работает, оставлено как основа схемы |
| 3 | Диагностика «блокировок»: UDP/53, TCP/53 таймауты до всех резолверов, ICMP и :443 до обычных сайтов работали | Ложный след — та же петля |
| 4 | Сброс пароля админа Technitium (удаление `auth.config` + рестарт) | Учётка пересоздалась как `admin`/`admin`; пароль сменён через API на значение из `.env` |
| 5 | Форвардеры провайдера по UDP (`92.50.178.5`, `81.30.199.5`) | Рабочий временный вариант; заменён — цель была уйти от провайдера |
| 6 | DoT `1.1.1.1:853` | Не работает: DPI режет TLS после успешного TCP-connect |
| 7 | DoH `https://cloudflare-dns.com/dns-query` без бутстрапа | Не работает: имя форвардера нечем резолвить (петля ещё была жива) |
| 8 | DoH + локальная зона `cloudflare-dns.com` → рабочие anycast IP | **Итоговое решение** |

### Итоговая архитектура

```
клиент → Keenetic (System profile → ${SERVER_IP}) → Technitium → DoH Cloudflare (закреплённые IP)
```

Условия работоспособности:

1. На Keenetic транзитные запросы **разрешены**
   (`no dns-proxy intercept enable`, затем `system configuration save`) —
   иначе петля с центральным резолвером в LAN.
2. Зона `cloudflare-dns.com` закрепляет бутстрап на незаблокированные IP.
3. Клиенты с жёстко прописанным внешним DNS обходят Technitium (транзит
   разрешён) — осознанный trade-off.

### Сброс пароля администратора

ENV `DNS_ADMIN_PASSWORD` применяется только при первичной инициализации.
Сброс существующего пароля:

```sh
docker compose down
sudo mv /storage/apps/technitium/etc/auth.config \
        /storage/apps/technitium/etc/auth.config.bak.$(date +%Y%m%d%H%M%S)
docker compose up -d          # учётка пересоздастся как admin/admin
```

Затем сменить пароль через API (`api/user/changePassword` с параметрами
`token`, `pass` — старый, `newPass` — новый) и записать его в `.env`.

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
