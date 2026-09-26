# Terraform: конфигурация ресурсов вне кластера

Слой управления тем, что **вне** кластера k0s. В репозитории уже три слоя, и у
каждого свой каталог: `ansible/` — хост, `apps/` и `platform/` — кластер. Ресурсы,
которыми нельзя управлять через Kubernetes, лежат здесь.

Инструмент и место запуска — `docs/adr/0008-terraform-tool-and-run-location.md`:
`terraform`, запуск с macOS, на сервере не устанавливается.

## Раскладка

Один каталог на root-модуль:

```text
terraform/
├── README.md
└── vault/
    ├── main.tf
    ├── policies.tf
    ├── roles.tf
    ├── k8s.tf
    └── .terraform.lock.hcl
```

Не один общий каталог на всё: у каждого root-модуля свой state и своя
блокировка, поэтому добавление второго модуля (`dns/` для публичной зоны) не
требует разделять существующий.

## `vault/` и `apps/vault/`

Это разные вещи, хотя имена похожи:

| Каталог | Что это |
| --- | --- |
| `apps/vault/` | сам Vault: Helm-чарт, PostgreSQL, секреты, маршрут |
| `terraform/vault/` | конфигурация **внутри** Vault: политики, auth-роли, пути |

## Запуск

```sh
cd terraform/vault
terraform init
terraform plan
```

`init` тянет провайдер из реестра HashiCorp, поэтому нужен доступ в интернет.

Провайдер настраивается окружением, а не кодом, поэтому блок `provider "vault"`
пустой:

- `address` читается из `VAULT_ADDR` — реальный домен коммитить нельзя, он
  живёт в untracked `platform/homelab/values.private.yaml`;
- `token` читается из `~/.vault-token`, куда его кладёт `vault login`, — токен в
  git не попадает;
- `skip_tls_verify` не задаётся: за Vault настоящий сертификат Let's Encrypt.

Первый запуск требует ручных шагов:

```sh
brew install vault
export VAULT_ADDR="https://vault.<домен>"
vault login
```

Токен — рабочий, с политикой `terraform` и дефолтной `default` (она даёт
`renew-self` и `revoke-self`, то есть ротация не требует root). У него должен
быть `update` на `auth/token/create`: по умолчанию провайдер выпускает себе
дочерний токен с коротким TTL. Отключать это через `skip_child_token` HashiCorp
прямо не рекомендует.

Имя токена можно задать через `VAULT_TOKEN_NAME` — в журнале аудита Vault будет
видно, каким запуском сделано изменение.

## Что коммитится

| Артефакт | В git |
| --- | --- |
| `*.tf` | да |
| `.terraform.lock.hcl` | да — пиннит версии и хеши провайдеров |
| `.terraform/`, `*.tfstate`, `*.tfplan` | нет, см. `.gitignore` |

## Управляемые ресурсы

Всё взято под управление через `terraform import`, а не создание: конфигурация
Vault существовала вручную, и `create` уничтожил бы её и создал заново. Порядок
внедрения — `docs/adr/0006-vault-secret-path-layout.md`, шаг 2.

| Файл | Ресурсы |
| --- | --- |
| `policies.tf` | политики `terraform`, `uptime-kuma`, `vso-reader` |
| `roles.tf` | роли `vso-reader`, `vso-uptime-kuma` в методе `kubernetes` |
| `k8s.tf` | метод `kubernetes`: адрес API и режим проверки JWT |

Секретов в state нет: политики и роли несут только правила доступа, а в
`auth/kubernetes/config` не заданы `token_reviewer_jwt` и `kubernetes_ca_cert` —
Vault берёт локальный CA и собственный токен пода, потому что работает в том же
кластере. Если `token_reviewer_jwt` когда-нибудь зададут, он попадёт в state
открытым текстом, и тогда потребуется write-only вариант `token_reviewer_jwt_wo`.

Каждый ресурс в state обязан иметь блок `resource` в конфигурации: иначе
следующий `apply` предложит его удалить, а `destroy` в Vault необратим.

Требования к переносимости конфигурации (никаких возможностей, которых нет в
`terraform`) сняты сменой инструмента; блок `encryption` не используется.
