# Terraform

Один каталог на root-модуль, у каждого свой state. State хранится в RustFS, в
git не попадает. Здесь — модули стенда `casa`; то, что относится к аккаунту
целиком, лежит в `infra/global/terraform/` и описано в его README.

## State

Все модули `infra/casa/terraform` и `infra/global/terraform` пишут state в бакет
`terraform-state` в RustFS (объявлен в `infra/casa/terraform/rustfs/state.tf`),
по ключу на модуль. Ключ начинается с области, к которой ресурс принадлежит:
`clusters/<кластер>/` или `global/` — то, что относится к аккаунту целиком, а не
к одному стенду.

```text
clusters/casa/forgejo/terraform.tfstate
clusters/casa/rustfs/terraform.tfstate
clusters/casa/technitium/terraform.tfstate
clusters/casa/uptime-kuma/terraform.tfstate
clusters/casa/vault/terraform.tfstate
clusters/casa/zitadel/terraform.tfstate
global/tailscale/terraform.tfstate
```

`tailscale` — единственный пока модуль уровня аккаунта: `acl.tf` описывает
политику tailnet, `dns.tf` — MagicDNS и split DNS, и то и другое общее для всех
кластеров (тег `tag:k8s` из того же `acl.tf` использует и `yc`).

Бэкенд — S3 с `use_lockfile`: лок берётся объектом `<key>.tflock` рядом со state,
поэтому два запуска одного модуля одновременно невозможны. Атомарность
conditional PUT на этом хранилище проверена: из двух параллельных `PUT` с
`If-None-Match: *` второй получает `412 PreconditionFailed`. Без этого лок был бы
фикцией.

Бакет версионируется, noncurrent-версии живут 30 дней — это окно отката, см.
«Восстановление state».

Креды приходят из окружения; в блоках `backend` их нет, иначе они осели бы в
`.terraform/`:

```sh macOS
read -rs AWS_ACCESS_KEY_ID && echo;     export AWS_ACCESS_KEY_ID
read -rs AWS_SECRET_ACCESS_KEY && echo; export AWS_SECRET_ACCESS_KEY
```

Значения — в Vault по пути `kv/rustfs/credentials` (`RUSTFS_ACCESS_KEY`,
`RUSTFS_SECRET_KEY`): это root-ключ RustFS, отдельного пользователя на бакет
хранилище не отдаёт. Те же переменные нужны провайдеру в модуле `rustfs`,
поэтому теперь они обязательны для любого модуля, а не только для него.

После смены конфигурации бэкенда запускать `terraform init -migrate-state`. Без
`init` команды падают с «Backend initialization required» — это ожидаемо, а не
поломка.

`infra/yc/terraform` в этом бакете не лежит: его state не должен зависеть от
кластера, который может быть пересобран (bootstrap-порядок), поэтому там state
локальный.

### Восстановление state

Выгрузить нужную версию объекта и вернуть её в работу:

```sh macOS
aws --endpoint-url https://s3.biplane.casa s3api list-object-versions \
  --bucket terraform-state --prefix casa/vault/terraform.tfstate \
  --query 'Versions[].{VersionId:VersionId,LastModified:LastModified}' --output table
```

```sh macOS
aws --endpoint-url https://s3.biplane.casa s3api get-object \
  --bucket terraform-state --key casa/vault/terraform.tfstate \
  --version-id <VersionId> terraform.tfstate.restore
```

```sh macOS
cd infra/casa/terraform/vault && terraform state push terraform.tfstate.restore
```

`state push` перезаписывает state целиком: сверить `serial` в выгруженном файле
с тем, что показывает `terraform state pull`, и не пушить файл от другой ревизии
конфигурации.

## Модули

| Модуль | Что описывает | Документация |
| --- | --- | --- |
| `forgejo/` | Защита ветки `main` репозитория `homelab` | `infra/casa/terraform/forgejo/README.md` |
| `vault/` | Политики, роли и kubernetes-auth в HashiCorp Vault | `infra/casa/terraform/vault/README.md` |
| `uptime-kuma/` | Мониторы, теги, status page и настройки Uptime Kuma | `infra/casa/terraform/uptime-kuma/README.md` |
| `zitadel/` | Организация, проект, OIDC-приложения, роли, членства, гранты и политика логина Zitadel | `infra/casa/terraform/zitadel/README.md` |
| `technitium/` | DNS-записи зоны стенда и bootstrap-зоны `cloudflare-dns.com` | `infra/casa/terraform/technitium/README.md` |
| `rustfs/` | Бакеты `mirror` и `terraform-state`, их policy и служебные настройки | `infra/casa/terraform/rustfs/README.md` |

## Запуск

Набор доступов у каждого модуля свой, он описан в README модуля — ссылки в
таблице выше. Общего «залогиниться один раз» нет: Vault, Technitium, Zitadel и
Uptime Kuma проверяют разные креды.

Одно требование общее для всех: `AWS_ACCESS_KEY_ID` и `AWS_SECRET_ACCESS_KEY`
(раздел «State» выше). Без них `init` и `plan` падают на чтении state ещё до
того, как дело дойдёт до провайдера модуля.

## Доступ к Zitadel

Провайдер получает путь к JSON-ключу service account (private key JWT), а не сам
ключ и не токен, поэтому приватный ключ не попадает ни в репозиторий, ни в
state. Ключ готовится один раз в консоли Zitadel, путь и роли описаны в
`infra/casa/terraform/zitadel/README.md`.

## Параметры

Параметры конкретного модуля лежат в неотслеживаемом `infra/casa/terraform/<модуль>/terraform.tfvars`
и в git не попадают. В репозитории только пример в README модуля.

## Секреты в state

Реквизиты доступа к API сервиса передаются провайдерам через окружение, а не
через блок `provider`: аргументы блока в state не сохраняются. Ресурсы, чьи
атрибуты содержат секреты, в этом репозитории не заводятся — пароль
администратора Vault в state не лежит, и по той же причине уведомления
Uptime Kuma остались за пределами Terraform. В `infra/casa/terraform/zitadel` секрет
`client_secret` приложений намеренно не импортируется: он остаётся в Vault,
а в state его нет.
