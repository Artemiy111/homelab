# Traefik

Traefik — активный обратный прокси этого репозитория. Маршрутизаторы используют
HTTPS-точку входа `websecure`, а `web` перенаправляет HTTP-запросы на HTTPS.
Порты 80 и 443 привязаны только к адресу `192.0.2.10` и не пробрасываются на
интернет-роутере.

## Настройка

Один раз создать общую сеть:

```sh
docker network create traefiknet
```

Создать локальный файл окружения:

```sh
cp .env.example .env
```

При использовании `scripts/bootstrap-platform.sh` файл создаётся автоматически,
а случайный пароль сохраняется в `TRAEFIK_DASHBOARD_PASSWORD` внутри `.env`.

`traefik.yaml` в Git не хранится: `bash init.sh` генерирует его из
`traefik.yaml.tpl`, подставляя домен из `DOMAIN`. При ручной подготовке вместо
`cp .env.example .env` выполните `bash init.sh` — он создаст и `.env`, и
`traefik.yaml`.

Для получения сертификата Let's Encrypt создать в <dns-provider> TSIG-ключ зоны
`example.net` и заполнить в `.env`:

```dotenv
RFC2136_NAMESERVER=ns1.<dns-provider>.com:53
RFC2136_TSIG_ALGORITHM=hmac-sha256.
RFC2136_TSIG_KEY=имя-ключа-из-<dns-provider>
RFC2136_TSIG_SECRET=секрет-из-<dns-provider>
```

TSIG-секрет не добавлять в Git. Он используется Traefik только для временного
создания TXT-записей DNS-01. Сертификаты и данные ACME сохраняются в
`/storage/apps/traefik/letsencrypt/acme.json` с правами `0600`.

Создать учётные данные панели. В `.env` хеш необходимо оставить в одинарных
кавычках, чтобы знаки доллара воспринимались буквально:

```sh
htpasswd -nbB admin 'choose-a-password'
```

Запустить Traefik:

```sh
docker compose up -d
```

После переключения клиентов на Pi-hole панель будет доступна по адресу
`https://traefik.example.net/dashboard/`. Завершающий слеш обязателен.

Сокет Docker подключён только для чтения. При этом он всё равно раскрывает
чувствительные метаданные Docker API; позднее его можно заменить ограничивающим
socket proxy.
