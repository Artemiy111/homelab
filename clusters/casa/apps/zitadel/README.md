# Zitadel

Zitadel — IdP homelab. Доступен по `https://id.biplane.casa/`,
- консоль — `/ui/console`
- вход — `/ui/v2/login`.

## Как устроено

Postgres поднимается кластером CloudNativePG: суперпользователь остаётся у
оператора, а ZITADEL работает под непривилегированной managed-ролью `zitadel` —
владельцем базы. Роль и база объявлены в `clusters/casa/platform/cnpg/`
(`zitadel-db.cluster.yaml`, `zitadel-db.databases.yaml`).

`ZITADEL_FIRSTINSTANCE_*` применяется только на пустой базе.

## Секреты

Доставляются из Vault через VSO: `VaultAuth` `vso-zitadel` и четыре
`VaultStaticSecret`.

| Путь в Vault | Secret | Ключи |
|---|---|---|
| `kv/zitadel/db` | `zitadel-db-auth` | `username`, `password` managed-роли CNPG |
| `kv/zitadel/admin` | `zitadel-admin` | `ADMIN_PASSWORD` |
| `kv/zitadel/masterkey` | `zitadel-masterkey` | `masterkey` |
| `kv/zitadel/login-service-key` | `zitadel-login-service-key` | `tls.crt`, `tls.key` |

## OIDC-клиент для oauth2-proxy

Приложение `Oauth Proxy` уже создано и импортировано в Terraform
(`infra/terraform/zitadel/applications.tf`). client_id и client_secret лежат в Vault:
`kv/oauth2-proxy/oidc`. Новые клиенты заводить через Terraform, а не в консоли.

## Содержимое инстанса

Организация `homelab`, проект, OIDC-приложения, роли, членства, гранты и
политика логина описаны в Terraform — `infra/terraform/zitadel/`. Разворачивается
инстанс здесь, `clusters/casa/apps/zitadel/`; Terraform управляет тем, что внутри.

Что осталось в консоли: human users, service account `homelab-service`,
системные объекты инстанса. Список и причины — `infra/terraform/zitadel/README.md`.

Эксплуатация — в `RUNBOOK.md`.
