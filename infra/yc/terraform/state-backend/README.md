# `state-backend` (Terraform)

Бакет Object Storage с версионированием, сервисный аккаунт `terraform-state` и
статический ключ, которым остальные модули `yc` читают и пишут свой state.

## Зачем отдельный модуль

Бэкенд нельзя создать тем же state, который в нём лежит: terraform сначала
поднимает бэкенд, затем читает из него состояние. Поэтому bootstrap-модуль
хранит state локально (в git не попадает), а всё остальное живёт в бакете.

## Что создаётся

| Ресурс | Что это |
| --- | --- |
| `yandex_storage_bucket.tfstate` | приватный бакет `homelab-tfstate-<cloud-id>`, версионирование включено, анонимный доступ закрыт |
| `yandex_storage_bucket_iam_binding.state` | роль `storage.editor` на бакет — только для сервисного аккаунта ниже |
| `yandex_iam_service_account.state` | `terraform-state` |
| `yandex_iam_service_account_static_access_key.state` | статический ключ для S3 API |

Версионирование — не украшение: S3-бэкенд перезаписывает один и тот же объект,
и без версий ошибка `apply` или неудачная миграция не оставляет точки возврата.

## Bootstrap

Роли сервисного аккаунта `terraform` (`vpc`, `compute`, `load-balancer`, `dns`)
не покрывают Object Storage и IAM, поэтому bootstrap выполняется IAM-токеном
пользователя CLI. Токен живёт около 12 часов и в файл не пишется.

```sh macOS
cd infra/yc/terraform/state-backend

export TF_CLI_CONFIG_FILE="$PWD/../.terraformrc"
export YC_TOKEN="$(yc iam create-token)"

unset YC_SERVICE_ACCOUNT_KEY_FILE
terraform init
terraform apply
```

`YC_TOKEN` и `YC_SERVICE_ACCOUNT_KEY_FILE` взаимоисключающие: если ключ
сервисного аккаунта уже экспортирован, его надо убрать из окружения.

## Ключ доступа

Ключ читается из вывода и кладётся в профиль `yc-tfstate` файла
`~/.aws/credentials`. В репозиторий и в переменные окружения он не попадает:

```sh macOS
terraform output -raw access_key
terraform output -raw secret_key
```

```ini
[yc-tfstate]
aws_access_key_id = <access_key>
aws_secret_access_key = <secret_key>
```

Именно этот профиль указан в `backend "s3"` модулей: `profile = "yc-tfstate"`.

## Как подключён модуль

В `main.tf` каждого root-модуля `yc`:

```hcl
terraform {
  backend "s3" {
    endpoints                   = { s3 = "https://storage.yandexcloud.net" }
    bucket                      = "homelab-tfstate-<cloud-id>"
    key                         = "yc/<модуль>/terraform.tfstate"
    region                      = "ru-central1"
    profile                     = "yc-tfstate"
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_lockfile                = true
  }
}
```

`skip_*` отключают проверки, которых Object Storage не умеет: он не отдаёт
регион, account id и не принимает заголовки контрольных сумм AWS. `use_lockfile`
включает блокировку через условную запись объекта: два одновременных `apply`
не перетирают state, второй получает отказ.

## Переезд существующего state

Первый `init` после появления блока видит локальный `terraform.tfstate` и
предлагает выбор. Перенос — `-migrate-state`:

```sh macOS
cd infra/yc/terraform/cluster
terraform init -migrate-state
```

Terraform спросит подтверждение копирования state в бакет. После ответа
локальный файл остаётся на диске как копия, но больше не читается; удалять его
можно только убедившись, что `terraform plan` работает и показывает no changes.

## Проверка

```sh macOS
cd infra/yc/terraform/cluster

terraform plan

# состояние лежит в бакете, а не на диске
AWS_PROFILE=yc-tfstate aws --endpoint-url https://storage.yandexcloud.net \
  s3 ls s3://homelab-tfstate-<cloud-id>/yc/cluster/

# блокировка: второй plan в другом терминале получает отказ
terraform plan
```

## Чего здесь не делать

- **Не удалять ключ через terraform**, пока им пользуется state других модулей:
  `destroy` в этом модуле снимает доступ к собственному state.
- **Не коммитить `terraform.tfstate` bootstrap-модуля**: в нём секрет ключа.
  Файл в `.gitignore`, но это защита от случайности, а не от осознанного
  `git add -f`.
- **Не отключать версионирование** ради экономии: это единственный способ
  откатить state после неудачного `apply`.
