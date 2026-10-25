# Matrix Authentication Service

MAS — OAuth 2.0/OpenID Provider для Matrix (MSC3861). Нужен из-за клиентов:
Element X не умеет легаси-SSO (`m.login.sso`), его единственный «непарольный»
вход — OAuth против OIDC-aware auth-сервера. Element Web продолжает
пользоваться легаси-схемой, пока Synapse не переведён на делегирование.

## Как устроен

MAS — источник истины по учёткам и токенам: Synapse перестаёт выдавать сессии и
только проверяет токены интроспекцией (`matrix_authentication_service` в его
конфиге). Люди приходят из Zitadel: приложение `Matrix Authentication Service` с
redirect `https://mas.<домен>/upstream/callback/<ulid>`, и тот же `<ulid>` стоит
`id` провайдера в конфиге. `synapse_idp_id: oidc-zitadel` нужен `syn2mas`, чтобы
перенести существующие маппинги upstream-IdP при миграции.

Листенеров два: `web` (discovery, human, oauth, compat, assets) смотрит наружу
через Traefik, `internal` отдаёт только `/health` для проб. Публично health не
торчит: он ничего не раскрывает, но и отвечать из LAN ему незачем.

`client_id` Zitadel — не секрет и лежит в `config.yaml` рядом с остальной
конфигурацией. Из Vault приходят только секреты: `kv/mas/oidc`
(`client_secret`), `kv/mas/secrets` (`matrix_secret`, `encryption`, ключи
подписи), `kv/mas/db` (пароль роли Postgres).

## Ограничения

- Одна реплика: `mas-cli server` держит и HTTP-сервер, и воркер. Горизонтальное
  масштабирование потребует разделить их на `--no-worker` и `mas-cli worker`.
- `passwords.enabled: false`: паролей нет, вход только через Zitadel.
- Пока Synapse не переведён на делегирование, MAS ни на что не влияет — это
  заготовка для миграции (issue #1581, этап 2). Текущий вход идёт через
  `oidc_providers` самого Synapse.

Проверка и обслуживание — [`RUNBOOK.md`](RUNBOOK.md).
