# RustFS: эксплуатация

## Использование

Пример с AWS CLI (path-style обязателен, регион произвольный):

```sh
aws --endpoint-url https://s3.${DOMAIN} \
    --no-verify-ssl s3 ls
```

Для самоподписанных сценариев вне браузера CA letsencrypt публичный, поэтому
достаточно стандартного доверия; флаг `--no-verify-ssl` нужен только при
обращении по IP.

## Обновление образа

Версия пинится по digest индекса, а не по тегу: `crane digest rustfs/rustfs:<версия>`
возвращает тот digest, который и нужно вписать в манифест. Тег без digest
означает, что при перезапуске пода может подняться другая сборка, чем та, что
проверяли.

Хранилище одно, без избыточности, поэтому порядок такой.

1. Снять инвентарь данных — с ним сравнивается результат после обновления:

   ```sh
   kubectl -n rustfs exec deploy/rustfs -- \
     sh -c 'find /data/mirror -type f | wc -l; du -sb /data/mirror | cut -f1'
   ```

2. Сделать снапшот тома Longhorn. Он нужен не ради диска, а из-за того, что
   новая версия может мигрировать раскладку на диске на месте, и тогда откат
   образа сам по себе данные не вернёт:

   ```sh
   kubectl -n rustfs get pvc rustfs-data -o jsonpath='{.spec.volumeName}'
   ```

   Имя из ответа подставить в `longhornvolume` и `spec.volume`:

   ```yaml
   apiVersion: longhorn.io/v1beta2
   kind: Snapshot
   metadata:
     name: rustfs-preupgrade-<дата>
     namespace: longhorn-system
     labels:
       longhornvolume: <volume>
   spec:
     volume: <volume>
     createSnapshot: true
   ```

   Готовность — `status.readyToUse: true`.

3. Смержить PR с новым digest. Argo применит манифест, под пересоздастся
   (`strategy: Recreate`, один реплика), S3 API недоступен всё время старта.

4. Проверить: `/health`, анонимное чтение из зеркала, число файлов и байт из
   шага 1 и отсутствие ошибок миграции в логах.

   ```sh
   kubectl -n rustfs logs deploy/rustfs --since=10m | grep -iE 'migrat|error|panic'
   ```

Откат: revert коммита возвращает прежний digest, но если данные уже мигрированы
— восстановить том из снапшота шага 2. Бакет `mirror` в худшем случае
пересобирается прогоном `mirror-sync`.

## Смена root-креденшелов

Смена root-креденшелов: обновить значение в Vault по пути `kv/rustfs/credentials`,
дождаться синка VSO и пересоздать под.
Учтите: креды применяются только при инициализации пустого `/data`; для смены
на существующих данных создать нового пользователя через консоль/API, а не
переопределять env.

## Зеркало артефактов

Форсировать прогон:

```sh
kubectl -n rustfs create job --from=cronjob/mirror-sync mirror-sync-manual
```

Проверка анонимного доступа:

```sh
kubectl -n rustfs exec deploy/rustfs -- \
  curl -fsS -o /dev/null -w '%{http_code}\n' \
  http://rustfs/mirror/kubeconform/0.8.0/kubeconform_0.8.0_linux_amd64.tar.gz
```

## Обновление ревизии CR-схем

Гейт `manifests` работает офлайн: схемы CR он берёт только из зеркала по
ревизии `CRD_SCHEMAS_REV`. Поэтому ревизия сначала публикуется, потом пинится —
PR, который поднимает пин раньше публикации, падает на своём же гейте.

1. Поднять `CRD_SCHEMAS_REV` в `apps/casa/rustfs/manifests/mirror-sync.cronjob.yaml`
   и смержить.
2. Дождаться синка Argo и прогнать Job:
   `kubectl -n rustfs create job --from=cronjob/mirror-sync mirror-sync-rev`.
3. Проверить, что объект появился:

   ```sh
   kubectl -n rustfs exec deploy/rustfs -- \
     curl -fsS -o /dev/null -w '%{http_code}\n' \
     http://rustfs/mirror/kubeconform-cr-schemas/<rev>/crds-catalog_<rev>.tar.gz
   ```

4. Поднять ту же ревизию в `scripts/kubeconform.sh` (дефолт `crd_catalog_rev`) и
   в `env.CRD_SCHEMAS_REV` обоих `030-kubeconform.yml`, смержить.

## Зеркало Terraform-провайдеров

Форсировать прогон (схемы и провайдеры в одном Job):

```sh
kubectl -n rustfs create job --from=cronjob/mirror-sync mirror-sync-manual
```

Проверить, что провайдеры на месте (имя файла собирается из адреса, версии и
платформы):

```sh
kubectl -n rustfs exec deploy/rustfs -- \
  curl -fsS -o /dev/null -w '%{http_code}\n' \
  http://rustfs/mirror/providers/registry.terraform.io/hashicorp/external/terraform-provider-external_2.4.2_linux_amd64.zip
```

Ожидается `200`. Job завершается `Complete`, когда новых провайдеров нет:
существующие объекты пропускаются, бакет append-only.

Если Job падает с «нет кредов прокси 3x-ui» — в Vault не заведено значение
`kv/3x-ui/@mirror-sync/egress` либо Secret `mirror-sync-egress` в namespace
`rustfs` ещё не доставлен. Если с «sha256 не входит в zh-хэши lock-файла» —
lock-файл и пакет в бакете расходятся, нужен разбор версии. Если с
«upload failed» — загрузка в RustFS не прошла; объекта в бакете нет, Job
завершается ненулевым кодом, прогонить заново.

Если Job падает с `OOMKilled`, смотреть надо не на размер пакета, а на
`dnf install -y git tar gzip`: скрипт доустанавливает `git` на ходу, и `libdnf`
на разборе метаданных репозиториев занимает 512–580 МиБ RSS — больше, чем любой
пакет провайдера. Пик `dnf` плавает от прогона к прогону (метаданные качаются
заново в каждом контейнере), поэтому на прежнем лимите падение было
непостоянным: часть ночей Job доходил до `Complete`. Запас по памяти у Job'а
считается по этому шагу, а не по заливке: `put-object` держит в памяти около
90 МиБ независимо от размера файла (измерено на пакетах 31 МБ и 200 МБ) —
aws-cli считает контрольную сумму потоком. Переменные
`AWS_REQUEST_CHECKSUM_CALCULATION=when_required` и
`AWS_RESPONSE_CHECKSUM_VALIDATION=when_required` на потребление памяти не влияют
(измерено) и только отключают проверку контрольной суммы, поэтому не заданы.

Загрузка идёт одним запросом `put-object`, а не `aws s3 cp`: `cp` режет файл
на части и шлёт их параллельно, RustFS на одном CPU отвечает на зависшие
части `503 ServiceUnavailable`, и крупные пакеты (провайдер `aws` — 174 МБ) не
загружаются. Один запрос такой пакет кладёт за 30-40 с.
