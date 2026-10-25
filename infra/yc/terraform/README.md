# yc (Terraform)

Провижининг кластера `yc` в Yandex Cloud. Один каталог на root-модуль, у
каждого свой state; state лежит в Object Storage, в git не попадает.

| Модуль | Что описывает | Документация |
| --- | --- | --- |
| `state-backend/` | Бакет Object Storage, сервисный аккаунт и ключ для S3-бэкенда остальных модулей | `infra/yc/terraform/state-backend/README.md` |
| `cluster/` | Две ВМ под kubespray в зонах `d`, `e`, внешний балансировщик на kube-api и публичная подзона в Cloud DNS | `infra/yc/terraform/cluster/README.md` |

## Бэкенд state

State модулей хранится в бакете `homelab-tfstate-<cloud-id>` (Object Storage,
версионирование и блокировка через `use_lockfile`). Бакет и ключ создаёт
`state-backend/` один раз; он же описывает, как разложить ключ по профилю
`yc-tfstate` в `~/.aws/credentials`.

Бэкенд прописан в `main.tf` каждого модуля статически: bucket, key и профиль —
не секреты, а подставить в `backend` переменные нельзя. Подробности,
bootstrap и переезд существующего state — в
`infra/yc/terraform/state-backend/README.md`.

## Переменные окружения

Провайдер `yandex-cloud/yandex` не читает профиль `yc` CLI: ему нужны свои
переменные. Три из них — про доступ, четвёртая — про зеркало провайдеров.

| Переменная | Значение | Откуда взять |
| --- | --- | --- |
| `YC_SERVICE_ACCOUNT_KEY_FILE` | путь к JSON-ключу сервисного аккаунта `terraform` | создаётся один раз командой ниже |
| `YC_CLOUD_ID` | идентификатор облака | `yc config get cloud-id` |
| `YC_FOLDER_ID` | идентификатор каталога | `yc config get folder-id` |
| `TF_CLI_CONFIG_FILE` | путь к `.terraformrc` в этом каталоге | уже лежит в репозитории |

Ключ сервисного аккаунта (сам аккаунт и его роли — в `cluster/README.md`):

```sh macOS
mkdir -p ~/.config/yc
yc iam key create --service-account-name terraform \
  --output ~/.config/yc/terraform-key.json
chmod 600 ~/.config/yc/terraform-key.json
```

Для разового плана сервисный аккаунт не обязателен: годится IAM-токен текущего
пользователя CLI, он живёт около 12 часов.

```sh macOS
export YC_TOKEN="$(yc iam create-token)"
```

Один способ за раз: если выставлены и `YC_TOKEN`, и ключ, выбирать придётся
провайдеру — лишнюю переменную убрать (`unset YC_TOKEN`).

Полный набор перед `terraform plan` (команды — из каталога модуля
`infra/yc/terraform/cluster`):

```sh macOS
export TF_CLI_CONFIG_FILE="$PWD/../.terraformrc"
export YC_SERVICE_ACCOUNT_KEY_FILE="$HOME/.config/yc/terraform-key.json"
export YC_CLOUD_ID="$(yc config get cloud-id)"
export YC_FOLDER_ID="$(yc config get folder-id)"

terraform init
terraform plan
```

`$PWD/../.terraformrc` — конфиг провайдеров лежит в `infra/yc/terraform/`, на
уровень выше модуля.

Реестр Terraform не отдаёт провайдера из России и отвечает `does not offer a
Terraform provider registry`. Поэтому `init` ходит через зеркало
`https://terraform-mirror.yandexcloud.net/`, а конфиг провайдеров лежит в
`.terraformrc` рядом с этим README. Terraform указывают на него переменной
`TF_CLI_CONFIG_FILE`, потому что свой конфиг в каталоге он не ищет; без неё и без
доступа к реестру `init` падает.

Аргументы `provider`-блока Terraform в state не сохраняет, поэтому credentials в
блок не кладутся: ключ не попадает ни в репозиторий, ни в state.
