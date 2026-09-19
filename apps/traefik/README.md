# Traefik

Traefik — активный обратный прокси этого репозитория. Маршрутизаторы используют
HTTPS-точку входа `websecure`, а `web` перенаправляет HTTP-запросы на HTTPS.
Порты 80 и 443 привязаны только к адресу `192.0.2.10` и не пробрасываются на
интернет-роутере.

Разворачивается манифестами в `platform/traefik/`.

## Настройка

Секреты traefik хранятся зашифрованными в `secrets.enc.env` (SOPS + age, см.
раздел «Секреты» в корневом README).

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
`/storage/apps/traefik/letsencrypt/acme.json` с правами `0600`.

После переключения клиентов на Technitium DNS панель будет доступна по адресу
`https://traefik.example.com/dashboard/`. Завершающий слеш обязателен.
