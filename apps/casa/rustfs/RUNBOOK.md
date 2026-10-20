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
lock-файл и пакет в бакете расходятся, нужен разбор версии.
