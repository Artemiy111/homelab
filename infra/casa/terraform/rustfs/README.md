# RustFS (Terraform)

Бакеты `mirror` и `terraform-state`, их policy и служебные настройки.
Развёртывание самого хранилища — `apps/casa/rustfs/`, здесь только бакеты через
S3 API: AWS-провайдер против кастомного эндпоинта RustFS.

## Запуск

С macOS провайдер ходит в `https://s3.<домен>` (через Traefik), поэтому нужен
маршрут в домашнюю сеть (Tailscale).

```sh macOS
cd infra/casa/terraform/rustfs
terraform init
terraform plan
```

## Доступ провайдера

Креды — root RustFS из Vault (`kv/rustfs/credentials`, ключи `RUSTFS_ACCESS_KEY` и
`RUSTFS_SECRET_KEY`); отдельного IAM-пользователя RustFS не отдаёт. Провайдер
берёт их из окружения, в блок `provider` они не пишутся, поэтому в state не
попадают. Ввод без истории оболочки:

```sh macOS
read -rs AWS_ACCESS_KEY_ID && echo
export AWS_ACCESS_KEY_ID
read -rs AWS_SECRET_ACCESS_KEY && echo
export AWS_SECRET_ACCESS_KEY
```

Провайдер настроен на workaround'ы S3-совместимого сервера:
`s3_use_path_style = true` (RustFS без virtual-host) и skip-флаги, чтобы
провайдер не ходил в AWS-only metadata/STS/account API.

## Значения

```hcl
domain = "example.com"   # тот же домен, что в Gateway (platform/casa/traefik/manifests/gateway-homelab.yaml)
```

Внутреннее значение, в git не идёт; реальное — в
`infra/casa/terraform/rustfs/terraform.tfvars` (gitignored).

## Что управляется

| Ресурс | Что |
| --- | --- |
| `aws_s3_bucket.mirror` | бакет `mirror` |
| `aws_s3_bucket_policy.mirror` | анонимный `s3:GetObject` на `mirror/*` — механизм доступа для CI |
| `aws_s3_bucket.state` | бакет `terraform-state` — state всех root-модулей `infra/casa/terraform` |
| `aws_s3_bucket_versioning.state` | версионирование объектов state |
| `aws_s3_bucket_public_access_block.state` | публичный доступ закрыт |
| `aws_s3_bucket_lifecycle_configuration.state` | noncurrent-версии удаляются через 30 дней |

Policy здесь не «висит просто так»: отдельного пользователя только на чтение
RustFS не отдаёт (IAM API нет, есть только root-креды), поэтому анонимный
`s3:GetObject` — единственный способ, которым CI читает зеркало. Снятие policy
выключает чтение всем потребителям сразу, включая внутрикластерный адрес:
анонимный `GET` получает `AccessDenied`, а не тихое «этот адрес закрыт» (#732).

Заливка объектов остаётся у CronJob `mirror-sync`
(`apps/casa/rustfs/manifests/mirror-sync.sh`, манифест `artifacts.tsv`); из скрипта убран
`ensure_bucket`, потому что бакет и policy теперь принадлежат Terraform.

## Бакет состояния Terraform

`terraform-state` объявлен здесь, а не отдельным модулем, по одной причине:
бакет должен существовать до `terraform init`, а модуль `rustfs` — единственный,
чей state при первом apply ещё локальный. Порядок такой: применить этот модуль
(`state.tf` создаёт бакет), затем перевести бэкенды остальных модулей
на этот бакет и последним — сам `rustfs`. Отдельный bootstrap-модуль дал бы
восьмой state, который тоже надо куда-то положить.

Версионирование здесь не украшение: каждый `apply` перезаписывает объект state,
и noncurrent-версии — единственный способ откатиться, если в state попала
ошибка. Lifecycle ограничивает их 30 днями, потому что объект лока
(`<key>.tflock`) перезаписывается на каждом `plan` и `apply`, и без правила
версии растут без предела.

Сам бакет закрыт: policy, как у `mirror`, у него нет, а anonymous-доступ
выключен явно. Содержимое — state модулей: там нет секретов по правилам
`infra/casa/terraform/README.md`, но есть внутренние значения, и публиковать их
незачем.

## Первый apply

Бакет и policy уже существуют, поэтому `imports.tf` переносит их в state.
Проверять надо план:

```sh macOS
terraform plan
```

Ожидается `No changes`. Если plan предлагает править policy — сравнить форму
JSON с тем, что положил скрипт, и не применять наугад. После apply `terraform
plan` обязан быть пустым.

## Чего модуль не делает

- **IAM.** RustFS не отдаёт IAM API, поэтому `aws_iam_*` здесь не работают;
  пользователи и ключи — root-креды из Vault.
- **Объекты.** Содержимое бакета (`artifacts.tsv`, схемы kubeconform) Terraform не
  загружает — это дело CronJob.
- **Другие бакеты.** Появятся под бэкапы CNPG и Forgejo — тогда добавляются сюда
  отдельными ресурсами.
