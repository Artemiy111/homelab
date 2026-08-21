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

Подготовить конфигурацию и запустить:

```sh
bash ./init.sh
docker compose up -d
docker compose ps
```

`init.sh` создаёт `.env` со случайным паролем дашборда
(`TRAEFIK_DASHBOARD_PASSWORD` и его хеш) и генерирует `traefik.yaml` из
`traefik.yaml.tpl`, подставляя домен из `DOMAIN`. Повторный запуск существующий
`.env` не перезаписывает, но заново рендерит `traefik.yaml` — поэтому после
заполнения `LETSENCRYPT_EMAIL` в `.env` выполните `bash ./init.sh` ещё раз.

Для получения сертификата Let's Encrypt создать в <dns-provider> TSIG-ключ зоны
`example.com` и заполнить в `.env` вместо заглушек:

```dotenv
RFC2136_NAMESERVER=ns1.<dns-provider>.com:53
RFC2136_TSIG_ALGORITHM=hmac-sha256.
RFC2136_TSIG_KEY=имя-ключа-из-<dns-provider>
RFC2136_TSIG_SECRET=секрет-из-<dns-provider>
```

TSIG-секрет не добавлять в Git. Он используется Traefik только для временного
создания TXT-записей DNS-01. Сертификаты и данные ACME сохраняются в
`$APPS_STORAGE_PATH/traefik/letsencrypt/acme.json` с правами `0600` (файл
создаёт `init.sh`).

После переключения клиентов на Technitium DNS панель будет доступна по адресу
`https://traefik.example.com/dashboard/`. Завершающий слеш обязателен.

Сокет Docker подключён только для чтения. При этом он всё равно раскрывает
чувствительные метаданные Docker API; позднее его можно заменить ограничивающим
socket proxy.
