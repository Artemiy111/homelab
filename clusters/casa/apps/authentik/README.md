# Authentik

Authentik — тестовый identity provider.
URL: `https://auth.example.com/`

Секреты сервиса — секретный ключ Authentik, пароль PostgreSQL, CIDR Traefik —
приходят из Vault.

## Вход только по passkey

Authentik поддерживает passwordless-аутентификацию через WebAuthn; правило
применяется одинаково к обычным пользователям и `akadmin`. Не включайте её до
регистрации хотя бы двух passkey для `akadmin` на разных устройствах.

У этого режима нет безопасного password fallback. Храните минимум две passkey
на независимых устройствах и заранее определите аварийный порядок
восстановления доступа.

## Хранилище

База — PostgreSQL в общем кластере CNPG `shared` (namespace `databases`,
эндпоинт `shared-rw.databases.svc.cluster.local:5432`). Роль `authentik`, база
`authentik` и NetworkPolicy объявлены в `clusters/casa/platform/cnpg/`; пароль роль берёт из
Secret'а `authentik-db-auth`, приложение — из своего Secret'а `authentik`
(ключ `AUTHENTIK_POSTGRESQL_PASSWORD`), поэтому менялся только хост. Данные
перенесены из локального `authentik-postgresql` дампом, старый Deployment снят.

Первый запуск, вход по passkey, проверка и обновление — в `RUNBOOK.md`.
