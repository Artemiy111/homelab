# Vault (Terraform)

Политики, роли и метод аутентификации `kubernetes` в HashiCorp Vault. Сам сервер
— `apps/casa/vault/`; здесь только доступы: какое приложение что читает.

## Что управляется

| Файл | Что описывает |
| --- | --- |
| `k8s.tf` | метод `auth/kubernetes` — Vault проверяет токен ServiceAccount через API кластера |
| `roles.tf` | роль на приложение: ServiceAccount `vso-<app>` в своём namespace и политика `app/<app>` |
| `policies.tf` | политика `terraform` — то, чем запускается сам модуль |
| `policies-db.tf` | политики `db/<app>` для CNPG: те же пути, что у приложения, но отдельным токеном оператора |
| `policies/` | политики приложений `app/<app>` |

## Запуск

Токен выдаётся из кластера и живёт 24 часа:

```sh
vault token create -policy=terraform -period=24h -orphan -display-name=terraform-macos
```

На macOS — логин и запуск:

```sh
vault login -address="https://vault.<домен>"

cd infra/casa/terraform/vault
terraform init
terraform plan
```

Переменные окружения не нужны: адрес Vault объявлен в `locals.tf`, токен
`terraform` берётся из `~/.vault-token`.

## Новый секрет приложения

1. Завести значение в Vault по пути `kv/<сервис>/<секрет>`
   (`docs/adr/0006-vault-secret-path-layout.md`).
2. Добавить в политику `app/<сервис>` два пути: `kv/data/…` и
   `kv/metadata/…`.
3. `terraform plan` — в выводе только добавленные пути.
4. `terraform apply`.
5. Проверить, что `VaultStaticSecret` юнита перешёл в `True`: без права VSO
   получает `permission denied` и Secret не создаёт.
