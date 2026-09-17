# RustFS — S3-совместимое объектное хранилище

RustFS — высокопроизводительное распределённое объектное хранилище с полным
S3 API (аналог MinIO, написан на Rust). Развёрнуто в режиме single-node
single-disk: без erasure coding и встроенной избыточности. Отказ диска = отказ
хранилища; резервные копии данных решаются отдельно.

## Доступ

| Что | Адрес |
|---|---|
| S3 API | `https://s3.${DOMAIN}` |
| Веб-консоль | `https://rustfs.${DOMAIN}` (редирект на базу `/rustfs/console/`) |

`RUSTFS_SERVER_DOMAINS` намеренно не задан: с ним ломается аутентификация
консоли (rustfs#887). Path-style запросы работают и без него.

Оба маршрута идут через Traefik (`traefiknet`), TLS — wildcard-сертификат
letsencrypt с entrypoint `websecure`. DNS подхватывается wildcard-записью
Technitium (`*.${DOMAIN}` → `${SERVER_IP}`).

Особенность маршрутизации: браузерная консоль по умолчанию считает S3-endpoint'ом
собственный хост и шлёт подписанные SigV4-запросы на `rustfs.${DOMAIN}`.
Поэтому Traefik направляет на порт 9000 (API) любые запросы к
`rustfs.${DOMAIN}` с заголовком `Authorization: AWS4-HMAC-SHA256`, путь
`/rustfs/console/*` — на порт 9001 (UI), а корень хоста редиректит на UI.
Убирать эти роутеры нельзя: без них вход в консоль ломается
(`SignatureDoesNotMatch`, см. rustfs#887, rustfs#3062).

Root-креденшелы хранилища — `rustfs/secrets.enc.env`:
`RUSTFS_ACCESS_KEY`, `RUSTFS_SECRET_KEY`. Логин в веб-консоль выполняется этими
же значениями.

## Структура

- `compose.yaml` — единственный сервис `rustfs`; образ запускается под
  `user: "1000:1000"` (вместо родного uid 10001), чтобы писать в bind mount
  без chown под root.
- Данные: `$APPS_STORAGE_PATH/rustfs/data`.
- Секреты: `secrets.enc.env` (SOPS поверх age).

## Использование

Пример с AWS CLI (path-style обязателен, регион произвольный):

```sh
aws --endpoint-url https://s3.${DOMAIN} \
    --no-verify-ssl s3 ls
```

Для самоподписанных сценариев вне браузера CA letsencrypt публичный, поэтому
достаточно стандартного доверия; флаг `--no-verify-ssl` нужен только при
обращении по IP.

## Эксплуатация

```sh
bash scripts/compose-secrets.sh rustfs up -d     # запуск/обновление
bash scripts/compose-secrets.sh rustfs logs -f   # логи
docker exec rustfs curl -fsS http://127.0.0.1:9000/health  # health изнутри
```

Смена root-креденшелов: отредактировать `secrets.enc.env` на сервере
(`sops rustfs/secrets.enc.env` от имени artlab) и пересоздать контейнер.
Учтите: креды применяются только при инициализации пустого `/data`; для смены
на существующих данных создать нового пользователя через консоль/API, а не
переопределять env.

## Ограничения текущей схемы

- Single-node single-disk: нет ни репликации, ни erasure coding.
- Хранилище не включено в бэкапы платформы; большие объёмы объектов
  бэкапировать побайтовым копированием каталога бессмысленно — использовать
  S3-репликацию или `rclone sync` на внешнее хранилище при необходимости.
