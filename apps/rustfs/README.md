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
Поэтому Traefik направляет на порт 80 (S3 API) любые запросы к
`rustfs.${DOMAIN}` с заголовком `Authorization: AWS4-HMAC-SHA256`, путь
`/rustfs/console/*` — на порт 9001 (UI), а корень хоста редиректит на UI.
Убирать эти роутеры нельзя: без них вход в консоль ломается
(`SignatureDoesNotMatch`, см. rustfs#887, rustfs#3062).

Root-креденшелы хранилища — в Vault (`kv/rustfs/credentials`):
`RUSTFS_ACCESS_KEY`, `RUSTFS_SECRET_KEY`. Логин в веб-консоль выполняется этими
же значениями.

## Структура

- Образ запускается под uid/gid `1000:1000` (вместо родного uid 10001),
  чтобы писать в том без chown под root.
- Данные хранятся в томе сервиса.
- Секреты: `kv/rustfs/credentials` (Vault).

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

Смена root-креденшелов: обновить значение в Vault по пути `kv/rustfs/credentials`,
дождаться синка VSO и пересоздать под.
Учтите: креды применяются только при инициализации пустого `/data`; для смены
на существующих данных создать нового пользователя через консоль/API, а не
переопределять env.

## Зеркало артефактов для CI

Бакет `mirror` — generic-хранилище заранее скачанных артефактов (бинарники,
tarball'ы), которые CI тянет анонимно по HTTP, не ходя в интернет:

```text
http://rustfs.rustfs.svc.cluster.local/mirror/<path>
```

Публичный адрес `https://s3.<домен>/mirror/<path>` тоже работает: безусловное
правило в `k8s/route.yaml` отдаёт анонимные запросы в S3 API, и public-read
политика бакета их допускает. Правило без `matches` должно оставаться
**последним** в списке: Gateway API неimplicit, приоритет отдаёт более
специфичным правилам (заголовок `Authorization`, префикс `/rustfs/console`,
точный путь `/`), а безусловное забирает всё остальное — в том числе анонимное
чтение зеркала. Потеря этого правила при переписывании маршрута уже случилась
(#728, `docs/incidents/0007`) и выглядит как 404 на существующем объекте.

Что зеркалировать — `apps/rustfs/artifacts.tsv` (`<path> <sha256> <url>`).
Скачивает и складывает CronJob `mirror-sync` (образ `amazon/aws-cli`); схемы
kubeconform он же собирает из git. Артефакты с известным sha256 проверяются
перед загрузкой, а CI — после скачивания. Бакет append-only: чтобы заменить
версию, удалить объект и перезапустить.

Схем Kubernetes два набора, `kubeconform-schemas/<ver>/`:

| Объект | Каталог внутри | Кто ищет |
| --- | --- | --- |
| `kubernetes-json-schema_<ver>_standalone.tar.gz` | `v<ver>-standalone/` | гейт без `-strict` |
| `kubernetes-json-schema_<ver>_standalone-strict.tar.gz` | `v<ver>-standalone-strict/` | гейт с `-strict` |

Разделение нужно флагу `-strict` в kubeconform: он подставляет в путь
`{{.StrictSuffix}}` и ищет схему в каталоге, которого в зеркале не было бы —
весь job падал бы с `could not find schema`. Оба набора собираются из одного
клона `yannh/kubernetes-json-schema`: sparse-checkout меняется между
`sparse-checkout set`, клон повторно не качается.

Схемы CR в зеркале нет: kubeconform тянет их с
`raw.githubusercontent.com/datreeio/CRDs-catalog` напрямую (issue #791). У job'ов
egress есть — проверено `wget` из контейнера `dind` пода `forgejo-runner`.
Зеркалом остаются бинарники и схемы Kubernetes: первое ради сверки sha256,
второе ради привязки к версии кластера, которой у схем CR нет.

Бакет `mirror` и его public-read policy — код в `terraform/rustfs`: правка бакета
в консоли будет перезаписана на следующем `terraform apply`, а CronJob
`mirror-sync` только заливает объекты.

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
  http://rustfs/mirror/kubeconform/0.8.0/kubeconform_0.8.0_linux_amd64.tar.gz
```

Доступ из job'ов CI обеспечивает NetworkPolicy `allow-ingress` (namespace
`forgejo` → порт 9000).

Часть артефактов со временем уходит на прозрачный кэш ATS (`apps/ats`): он сам
разворачивает `302` с GitHub Releases, поэтому версию не нужно сопровождать
руками. Для таких артефактов запись в `artifacts.tsv` остаётся оффлайн-фолбэком
(в бакете объект уже есть), а workflow тянет файл из ATS. Так сделано для `bun`
(workflow `commitlint`).

## Ограничения текущей схемы

- Single-node single-disk: нет ни репликации, ни erasure coding.
- Хранилище не включено в бэкапы платформы; большие объёмы объектов
  бэкапировать побайтовым копированием каталога бессмысленно — использовать
  S3-репликацию или `rclone sync` на внешнее хранилище при необходимости.
