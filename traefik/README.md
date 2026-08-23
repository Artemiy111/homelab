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
bash scripts/compose-secrets.sh traefik config --quiet
bash scripts/compose-secrets.sh traefik up -d
docker compose ps
```

Секреты traefik хранятся зашифрованными в `secrets.enc.env` (SOPS + age, см.
раздел «Секреты» в корневом README) и передаются в рантайме через
`sops exec-env`: plaintext-файл `.env` не создаётся. `init.sh` создаёт
каталог ACME и рендерит `traefik.yaml` из `traefik.tpl.yaml`, подставляя
домен из `DOMAIN` и email из расшифрованных секретов (`LETSENCRYPT_EMAIL`).
После изменения секретов (`sops secrets.enc.env` на сервере) перезапустите
контейнер через `scripts/compose-secrets.sh`.

Для получения сертификата Let's Encrypt создать в <dns-provider> TSIG-ключ зоны
`example.com` и заполнить значения в `secrets.enc.env` вместо заглушек:

```dotenv
RFC2136_NAMESERVER=ns1.<dns-provider>.com:53
RFC2136_TSIG_ALGORITHM=hmac-sha256.
RFC2136_TSIG_KEY=имя-ключа-из-<dns-provider>
RFC2136_TSIG_SECRET=секрет-из-<dns-provider>
```

TSIG-секрет не хранится в Git в открытом виде: он зашифрован внутри
`secrets.enc.env`. Сертификаты и данные ACME сохраняются в
`$APPS_STORAGE_PATH/traefik/letsencrypt/acme.json` с правами `0600` (файл
создаёт `init.sh`).

После переключения клиентов на Technitium DNS панель будет доступна по адресу
`https://traefik.example.com/dashboard/`. Завершающий слеш обязателен.

Сокет Docker подключён только для чтения. При этом он всё равно раскрывает
чувствительные метаданные Docker API; позднее его можно заменить ограничивающим
socket proxy.
