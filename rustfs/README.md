# RustFS — S3-совместимое объектное хранилище

RustFS — высокопроизводительное распределённое объектное хранилище с полным
S3 API (аналог MinIO, написан на Rust). Развёрнуто в режиме single-node
single-disk: без erasure coding и встроенной избыточности. Отказ диска = отказ
хранилища; резервные копии данных решаются отдельно (restic и т.п.).

## Доступ

| Что | Адрес |
|---|---|
| S3 API | `https://s3.${DOMAIN}` |
| Веб-консоль | `https://rustfs.${DOMAIN}` (редирект на базу `/rustfs/console/`) |

Оба маршрута идут через Traefik (`traefiknet`), TLS — wildcard-сертификат
letsencrypt с entrypoint `websecure`. DNS подхватывается wildcard-записью
Technitium (`*.${DOMAIN}` → `${SERVER_IP}`).

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

Пример restic поверх S3:

```sh
RESTIC_REPOSITORY="s3:https://s3.${DOMAIN}/backups" restic init
```

Из других контейнеров хоста сервис доступен по имени `rustfs:9000` после
подключения к сети `traefiknet`.

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
- Хранилище не включено в restic-бэкапы платформы; большие объёмы объектов
  бэкапировать побайтовым копированием каталога бессмысленно — использовать
  S3-репликацию или `rclone sync` на внешнее хранилище при необходимости.
