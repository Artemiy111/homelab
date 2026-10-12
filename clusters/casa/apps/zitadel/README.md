# Zitadel

Zitadel — IdP homelab. Доступен через Traefik по `https://id.<домен>/`,
где `<домен>` — литерал в манифестах юнита;
- консоль — `/ui/console`
- вход — `/ui/v2/login`.

## Первый запуск

Postgres поднимается кластером CloudNativePG: суперпользователь остаётся у
оператора, а ZITADEL работает под непривилегированной managed-ролью `zitadel` —
владельцем базы. Роль и база объявлены в `clusters/casa/platform/cnpg/`
(`zitadel-db.cluster.yaml`, `zitadel-db.databases.yaml`).

Админ логинится как `admin@zitadel.id.<домен>` (org по умолчанию —
`zitadel`). Принудительная смена пароля выключена
(`PASSWORDCHANGEREQUIRED=false`): пароль генерируется случайно и лежит в Vault,
менять его при первом входе не требуется.

`ZITADEL_FIRSTINSTANCE_*` применяется только на пустой базе.

## Секреты

Доставляются из Vault через VSO: `VaultAuth` `vso-zitadel` и четыре
`VaultStaticSecret` в `manifests/`.

| Путь в Vault | Secret | Ключи |
|---|---|---|
| `kv/zitadel/db` | `zitadel-db-auth` | `username`, `password` managed-роли CNPG |
| `kv/zitadel/admin` | `zitadel-admin` | `ADMIN_PASSWORD` |
| `kv/zitadel/masterkey` | `zitadel-masterkey` | `masterkey` |
| `kv/zitadel/login-service-key` | `zitadel-login-service-key` | `tls.crt`, `tls.key` |

- `zitadel-db-auth` читает и приложение, и CNPG для managed-роли `zitadel`
  (`platform/cnpg/zitadel-db.cluster.yaml`): один путь, один Secret, два
  потребителя (ADR 0006, правило 2).
- Masterkey контейнер получает переменной `ZITADEL_MASTERKEY`
  (`--masterkeyFromEnv`). Ключ менять нельзя: им зашифрованы секреты, замена
  делает данные нечитаемыми. Единственная копия — Vault.
- login-client аутентифицируется X.509-парой вместо PAT-файла:
  `zitadel-login-service-key` (`tls.crt`/`tls.key`). Публичная часть монтируется в
  `zitadel` и описана в `config/zitadel.yaml` (`SystemAPIUsers`), приватная — в
  `zitadel-login` (`ZITADEL_LOGINCLIENT_KEYFILE`).

## Passkey-only

См. `docs/research/authentication-services.md` (этап 2). Коротко: в
Organization Settings → Login Behavior and Security поставить «Passkey Login» =
Allowed; пользователей регистрировать только passkey (отдельная ссылка
регистрации), пароль не задавать. «Local authentication allowed» не выключать —
это отключит и passkey.

Одноразовую ссылку на регистрацию passkey без SMTP выдаёт
`zitadel/zitadel-passkey-link.sh` (нужен PAT администратора). Домен передаётся
переменной `DOMAIN` — тот же, что в бывшем чарте platform/homelab; вместо
неё можно задать `ZITADEL_HOST`:

```sh
DOMAIN=example.com ZITADEL_PAT=... ./zitadel/zitadel-passkey-link.sh
```

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

## Обновление

Проверять release notes: после 4.11 были passkey-регрессии (#11656, #11682),
в 4.16.1 — #12473. Версии `zitadel` и `login` закреплены в манифестах и должны
обновляться одним тегом.
