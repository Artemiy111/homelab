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

Оба маршрута идут через Traefik, TLS — wildcard-сертификат letsencrypt с
entrypoint `websecure`. DNS подхватывается wildcard-записью Technitium
(`*.${DOMAIN}` → `${HOST_IP}`).

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

- Образ запускается под uid/gid `1000:1000` (вместо родного uid 10001),
  чтобы писать в том без chown под root.
- Данные хранятся в томе сервиса.
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

Разворачивается через kustomize: `kubectl apply -k apps/rustfs`.

Смена root-креденшелов: отредактировать `secrets.enc.env` на сервере
(`sops rustfs/secrets.enc.env` от имени artlab) и пересоздать под.
Учтите: креды применяются только при инициализации пустого `/data`; для смены
на существующих данных создать нового пользователя через консоль/API, а не
переопределять env.

## Зеркало артефактов для CI

Бакет `mirror` — generic-хранилище заранее скачанных артефактов (бинарники,
tarball'ы), которые CI тянет анонимно по HTTP, не ходя в интернет:

```text
http://rustfs.rustfs.svc.cluster.local:9000/mirror/<path>
```

Что зеркалировать — `apps/rustfs/artifacts.tsv` (`<path> <sha256> <url>`).
Скачивает и складывает CronJob `mirror-sync` (образ `amazon/aws-cli`; egress
есть только у него); схемы kubeconform он же собирает из git. Артефакты с
известным sha256 проверяются перед загрузкой, а CI — после скачивания. Бакет
append-only: чтобы заменить версию, удалить объект и перезапустить.

Скрипт (`mirror-sync.sh`) и манифест (`artifacts.tsv`) едут в ConfigMap
`mirror-sync` через kustomize — отдельного шага нет:

```sh
kubectl apply -k apps/rustfs
kubectl -n rustfs create job --from=cronjob/mirror-sync mirror-sync-manual
```

Проверка анонимного доступа:

```sh
kubectl -n rustfs exec deploy/rustfs -- \
  curl -fsS -o /dev/null -w '%{http_code}\n' \
  http://rustfs:9000/mirror/kubeconform/0.8.0/kubeconform_0.8.0_linux_amd64.tar.gz
```

Доступ из job'ов CI обеспечивает NetworkPolicy `allow-ingress` (namespace
`forgejo` → порт 9000).

## Ограничения текущей схемы

- Single-node single-disk: нет ни репликации, ни erasure coding.
- Хранилище не включено в бэкапы платформы; большие объёмы объектов
  бэкапировать побайтовым копированием каталога бессмысленно — использовать
  S3-репликацию или `rclone sync` на внешнее хранилище при необходимости.
