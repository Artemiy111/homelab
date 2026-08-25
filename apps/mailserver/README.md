# Mailserver (Stalwart + Bulwark)

Почтовый сервер [Stalwart](https://stalwarthq.com) с веб-почтой
[Bulwark](https://github.com/bulwarkmail). Stalwart совмещает MTА, SMTP, IMAP
и JMAP в одном контейнере; Bulwark — лёгкий JMAP-клиент поверх него.

- SMTP: `25` (приём), `587` (submission)
- IMAP: `993`
- JMAP / API Stalwart: порт `8080`, за Traefik на
  `https://mailserver.example.com/`
- Веб-почта Bulwark: `https://mail.example.com/`

## Запуск

```sh
bash scripts/bootstrap-platform.sh mailserver
```

`init.sh` создаёт каталоги данных и генерирует секреты в зашифрованном
`secrets.enc.env` (домен подставляется из `DOMAIN`, случайный пароль
администратора — в `STALWART_ADMIN_PASS`). Повторный запуск их не меняет.

## Управление

Учётные данные администратора Stalwart (логин `admin`): в
секреты сервиса — `STALWART_ADMIN_USER` / `STALWART_ADMIN_PASS`. Первый вход
выполняется через консоль восстановления:

```sh
docker exec -it mailserver stalwart-cli recovery-login
```

Полученный одноразовый URL открывает веб-интерфейс администрирования. После
входа задайте пароль администратора сами и заведите пользователей
(Accounts → Add account). Стартовый пароль из секретов служит только для
восстановления.

## Хранение данных

`JMAP_SERVER_URL` в `compose.yaml` указывает на публичный HTTPS-адрес
админки Stalwart (`https://mailserver.<домен>`), а не на внутренний
`http://mailserver:8080`: Bulwark v1.8 выполняет обнаружение JMAP-сессии из
браузера, и внутренний docker-хостнейм там недоступен. Публичный адрес
обходит и CSP (`connect-src 'self' https:`), и недоступность `mailserver` вне
сети Docker.

- `$APPS_STORAGE_PATH/mailserver/etc` — конфигурация Stalwart (образ монтирует в `/etc/stalwart`)
- `$APPS_STORAGE_PATH/mailserver/data` — база Stalwart (каталоги, почта)
- `$APPS_STORAGE_PATH/mailserver/mail` — данные Bulwark

## DNS и сертификаты

Сертификаты для `mailserver.*` и `mail.*` выпускает Traefik (DNS-01 через
<dns-provider>). Записи `A`/`AAAA` на эти имена должны указывать на сервер.

Обратите внимание: публикация порта `25` на роутере требует, чтобы провайдер не
блокировал входящий SMTP. Порт `587` — гарантированная альтернатива для
клиентов.