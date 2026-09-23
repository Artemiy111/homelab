# GlitchTip

GlitchTip — сбор ошибок приложений, совместимый с Sentry SDK.
URL: `https://glitchtip.example.com/`

Разворачивается манифестами в apps/glitchtip/k8s/.

## Первый запуск

Миграции БД выполняются init-контейнером перед стартом `web`; повторный запуск
идемпотентен.

## Хранилище

База — PostgreSQL в общем кластере CNPG `shared` (namespace `databases`,
эндпоинт `shared-rw.databases.svc.cluster.local:5432`). Роль `glitchtip`, база
`glitchtip` и NetworkPolicy объявлены в `platform/cnpg/`; пароль роль берёт из
Secret'а `glitchtip-db-auth`, а приложение — из своего Secret'а `glitchtip`
(ключ `POSTGRES_PASSWORD`), поэтому в `DATABASE_URL` менялся только хост. Данные
перенесены из локального `glitchtip-postgres` дампом (`pg_dump`/`pg_restore`),
старый Deployment снят.

## Вход через Zitadel (OIDC)

Провайдер настраивается переменными из `secrets.enc.env` — вручную ничего в БД
добавлять не нужно:

- `GLITCHTIP_CLIENT_ID`, `GLITCHTIP_CLIENT_SECRET` — учётные данные
  OIDC-приложения Zitadel;
- `ENABLE_SOCIAL_APPS_USER_REGISTRATION=true` — первый вход создаёт
  пользователя автоматически (независимо от закрытой обычной регистрации);
- `SOCIAL_AUTH_BLOCK_PRIVATE_IPS=false` — разрешает discovery к IdP в LAN.

Приложение в Zitadel: Redirect URI
`https://glitchtip.example.com/accounts/oidc/zitadel/login/callback/`,
auth method `CODE` (Basic), grant Authorization Code. Init-контейнер при каждом
старте синхронизирует SocialApp с переменными окружения; если переменные
пустые — пропуск.

При первом входе зарегистрировать учётную запись администратора. Регистрация
новых пользователей закрыта (`ENABLE_USER_REGISTRATION=false`), создание
организаций разрешено любому вошедшему (`ENABLE_ORGANIZATION_CREATION=true`).

## Подключение приложений

В проекте GlitchTip создать DSN вида:

```
https://<public-key>@glitchtip.example.com/<project-id>
```

и указать его в Sentry SDK приложения.

## Проверка

```sh
curl --resolve glitchtip.example.com:443:<node1-ip> \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://glitchtip.example.com/auth/login/
```

Ожидаемый ответ: `200`.
