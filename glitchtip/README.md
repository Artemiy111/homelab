# GlitchTip

`https://glitchtip.example.com/`

GlitchTip — сбор ошибок приложений, совместимый с Sentry SDK. 

Образ закреплён на мажорной версии `6` (переменная `GLITCHTIP_VERSION`).
Постоянные данные находятся в `$APPS_STORAGE_PATH/glitchtip` и входят в общий
Restic snapshot.

## Первый запуск

Из каталога `glitchtip` выполнить:

```sh
bash ./init.sh
docker compose up -d
docker compose ps
```

Секреты (`SECRET_KEY`, пароль PostgreSQL) лежат в зашифрованном
`secrets.enc.env` (SOPS + age) и подставляются через `sops exec-env`
(см. `scripts/compose-secrets.sh`). Plaintext `.env` не создаётся.

Миграции БД выполняются one-shot контейнером `glitchtip-migrate` перед
стартом `web` (зависимость `service_completed_successfully`); повторный запуск
идемпотентен.

При первом входе зарегистрировать учётную запись администратора. Регистрация
новых пользователей закрыта (`ENABLE_USER_REGISTRATION=false`), создание
организаций разрешено любому вошедшему (`ENABLE_ORGANIZATION_CREATION=true`).

## Подключение приложений

В проекте GlitchTip создать DSN вида:

```
https://<public-key>@glitchtip.example.com/<project-id>
```

и указать его в Sentry SDK приложения. Для локальных клиентов, использующих
Technitium DNS, домен резолвится в LAN без доступа в интернет.

## Проверка

```sh
curl --resolve glitchtip.${DOMAIN}:443:192.0.2.10 \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://glitchtip.${DOMAIN}/auth/login/
```

Ожидаемый ответ: `200`.
