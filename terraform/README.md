# Terraform

Один каталог на root-модуль, у каждого свой state. State локальный на macOS,
в git не попадает.

## Модули

| Модуль | Что описывает | Документация |
| --- | --- | --- |
| `vault/` | Политики, роли и kubernetes-auth в HashiCorp Vault | `apps/vault/README.md` |
| `uptime-kuma/` | Мониторы, теги, status page и настройки Uptime Kuma | `terraform/uptime-kuma/README.md` |

## Запуск

```sh cluster
# Создать токен
vault token create -policy=terraform -period=24h -orphan -display-name=terraform-macos
```

```sh macOS
# Залогиниться на macOS
export VAULT_ADDR="https://vault.<домен>"
vault login
```

```sh macOS
cd terraform/vault
terraform init
terraform plan
```

Значения окружения для `terraform/vault` не нужны: провайдер берёт адрес из
`VAULT_ADDR`, токен — из `~/.vault-token`. У `terraform/uptime-kuma` свой
набор, он описан в его README.

## Параметры

Параметры конкретного модуля лежат в неотслеживаемом `terraform/<модуль>/terraform.tfvars`
и в git не попадают. В репозитории только пример в README модуля.

## Секреты в state

Реквизиты доступа к API сервиса передаются провайдерам через окружение, а не
через блок `provider`: аргументы блока в state не сохраняются. Ресурсы, чьи
атрибуты содержат секреты, в этом репозитории не заводятся — пароль
администратора Vault в state не лежит, и по той же причине уведомления
Uptime Kuma остались за пределами Terraform.
