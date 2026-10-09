# Zitadel

Zitadel — IdP homelab. Доступен через Traefik по `https://id.<домен>/`,
где `<домен>` — `config.domain` из `platform/homelab/values.yaml`;
- консоль — `/ui/console`
- вход — `/ui/v2/login`.

## Первый запуск

Postgres поднимается кластером CloudNativePG: суперпользователь остаётся у
оператора, а ZITADEL работает под непривилегированной managed-ролью `zitadel` —
владельцем базы. Роль и база объявлены в `platform/cnpg/`
(`zitadel-db.cluster.yaml`, `zitadel-db.databases.yaml`).

Админ логинится как `admin@zitadel.id.<домен>` (org по умолчанию —
`zitadel`). Принудительная смена пароля выключена
(`PASSWORDCHANGEREQUIRED=false`): пароль генерируется случайно и лежит в
зашифрованных секретах, менять его при первом входе не требуется.

`ZITADEL_FIRSTINSTANCE_*` применяется только на пустой базе.

## Секреты

- Masterkey — SealedSecret `zitadel-masterkey` (ключ `masterkey`); контейнер
  получает его переменной `ZITADEL_MASTERKEY` (`--masterkeyFromEnv`). Ключ менять
  нельзя: им зашифрованы секреты, замена делает данные нечитаемыми. Значение
  лежит и в `secrets.enc.env` (ключ `MASTERKEY`) — восстановимая копия.
- login-client аутентифицируется X.509-парой вместо PAT-файла: SealedSecret
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
`zitadel/zitadel-passkey-link.sh` (нужен PAT администратора). Домен скрипт
берёт из `platform/homelab/values.yaml`, тот же что у `ZITADEL_EXTERNALDOMAIN`;
переопределяется `DOMAIN` или `ZITADEL_HOST`:

```sh
ZITADEL_PAT=... ./zitadel/zitadel-passkey-link.sh
```

## OIDC-клиент для oauth2-proxy

Приложение `Oauth Proxy` уже создано и импортировано в Terraform
(`terraform/zitadel/applications.tf`). client_id и client_secret лежат в Vault:
`kv/oauth2-proxy/oidc`. Новые клиенты заводить через Terraform, а не в консоли.

## Содержимое инстанса

Организация `homelab`, проект, OIDC-приложения, роли, членства, гранты и
политика логина описаны в Terraform — `terraform/zitadel/`. Разворачивается
инстанс здесь, `apps/zitadel/`; Terraform управляет тем, что внутри.

Что осталось в консоли: human users, service account `homelab-service`,
системные объекты инстанса. Список и причины — `terraform/zitadel/README.md`.

## Обновление

Проверять release notes: после 4.11 были passkey-регрессии (#11656, #11682),
в 4.16.1 — #12473. Версии `zitadel` и `login` закреплены в манифестах и должны
обновляться одним тегом.
