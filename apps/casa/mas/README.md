# Matrix Authentication Service

MAS — OAuth 2.0/OpenID Provider для Matrix (MSC3861). Нужен из-за клиентов:
Element X не умеет легаси-SSO (`m.login.sso`), его единственный «непарольный»
вход — OAuth против OIDC-aware auth-сервера. Через MAS ходят все клиенты:
Synapse переведён на делегирование и сам сессий не выдаёт.

## Как устроен

MAS — источник истины по учёткам и токенам: Synapse перестаёт выдавать сессии и
только проверяет токены интроспекцией (`matrix_authentication_service` в его
конфиге). Люди приходят из Zitadel: приложение `Matrix Authentication Service` с
redirect `https://mas.<домен>/upstream/callback/<ulid>`, и тот же `<ulid>` стоит
`id` провайдера в конфиге. `synapse_idp_id: oidc-zitadel` нужен `syn2mas`, чтобы
перенести существующие маппинги upstream-IdP при миграции.

Листенеров два: `web` (discovery, human, oauth, compat, assets, adminapi)
смотрит наружу через Traefik, `internal` отдаёт только `/health` для проб.
Публично health не торчит: он ничего не раскрывает, но и отвечать из LAN ему
незачем.

`adminapi` включён в публичном листенере, потому что его вызывает браузер:
Element Admin ходит в `/api/admin/v1` с клиента. Сам по себе ресурс ничего не
открывает — доступ гейтится скоупом `urn:mas:admin`, а его MAS выдаёт только
пользователю с `can_request_admin`.

`client_id` Zitadel — не секрет и лежит в `config.yaml` рядом с остальной
конфигурацией. Из Vault приходят только секреты: `kv/mas/oidc`
(`client_secret`), `kv/mas/secrets` (`matrix_secret`, `encryption`, ключи
подписи), `kv/mas/db` (пароль роли Postgres).

## Ограничения

- Одна реплика: `mas-cli server` держит и HTTP-сервер, и воркер. Горизонтальное
  масштабирование потребует разделить их на `--no-worker` и `mas-cli worker`.
- `passwords.enabled: false`: паролей нет, вход только через Zitadel.
- Признак админа — `can_request_admin` у пользователя MAS. Флаг `admin` в
  Synapse после перевода на делегирование админских прав не даёт: скоуп
  `urn:synapse:admin:*` выдаёт MAS.

Проверка и обслуживание — [`RUNBOOK.md`](RUNBOOK.md).
