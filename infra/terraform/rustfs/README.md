# RustFS (Terraform)

Бакет `mirror` и его public-read policy. Развёртывание самого хранилища —
`clusters/casa/apps/rustfs/`, здесь только бакет через S3 API: AWS-провайдер против кастомного
эндпоинта RustFS.

## Запуск

С macOS провайдер ходит в `https://s3.<домен>` (через Traefik), поэтому нужен
маршрут в домашнюю сеть (Tailscale).

```sh macOS
cd infra/terraform/rustfs
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
domain = "example.com"   # тот же домен, что в clusters/casa/platform/homelab
```

Внутреннее значение, в git не идёт; реальное — в
`infra/terraform/rustfs/terraform.tfvars` (gitignored).

## Что управляется

| Ресурс | Что |
| --- | --- |
| `aws_s3_bucket.mirror` | бакет `mirror` |
| `aws_s3_bucket_policy.mirror` | public-read: анонимный `s3:GetObject` на `mirror/*` |

Заливка объектов остаётся у CronJob `mirror-sync`
(`clusters/casa/apps/rustfs/mirror-sync.sh`, манифест `artifacts.tsv`); из скрипта убран
`ensure_bucket`, потому что бакет и policy теперь принадлежат Terraform.

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
