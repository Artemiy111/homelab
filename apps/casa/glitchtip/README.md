# GlitchTip

GlitchTip — сбор ошибок приложений, совместимый с Sentry SDK.
URL: `https://glitchtip.example.com/`

## Хранилище

Единственное состояние GlitchTip — PostgreSQL в общем кластере CNPG `shared`:
роль, база и NetworkPolicy объявлены в `platform/casa/cnpg/`. На диске лежит
только том Valkey — очередь задач, кэш и сессии; их потеря стоит разлогина и
повторной постановки периодических задач.

Из этого следует, что база восстановима без дампа: схему создают миграции при
старте пода, а конфигурацию — манифесты и Vault. Теряются только учётные записи,
проекты и события, поэтому полное пересоздание — штатная операция, а не авария.
Порядок — в `RUNBOOK.md`.

Артефакты загрузки (source maps, DIF) — отдельный том, смонтированный и в web, и
в worker: web принимает чанки, worker собирает из них файл. Без общего тома
сборка падает с `FileNotFoundError` на `/code/uploads/...`, причём загрузка
выглядит успешной, а артефактов в базе нет. Том `ReadWriteOnce` — на одноузловом
кластере его можно смонтировать в два пода, на многоузловом понадобится RWX или
S3-хранилище. Потеря тома стоит только повторной загрузки карт.

## Вход через Zitadel (OIDC)

Задать OIDC-приложение переменными окружения GlitchTip не умеет: в настройках
есть только URL'ы отдельных провайдеров (`gitlab`, `gitea`, `nextcloud`,
`microsoft`). Штатный путь upstream — завести `SocialApp` в Django admin, а
появившийся в v6 per-org SSO рассчитан на уже существующую организацию и
показывает провайдера только на её странице входа.

Поэтому приложение Zitadel создаётся декларативно: init-контейнер web на каждом
старте выполняет `bootstrap.configmap.yaml` — upsert `SocialApp` с
`provider_id` `zitadel` из `GLITCHTIP_CLIENT_ID` и `GLITCHTIP_CLIENT_SECRET`
(Vault). Пустые переменные — шаг пропускается. `provider_id` входит в callback
URL, поэтому его переименование требует правки redirect URI в Zitadel.

Приложение в Zitadel: Redirect URI
`https://glitchtip.example.com/accounts/oidc/zitadel/login/callback/`,
auth method `CODE` (Basic), grant Authorization Code.

Вокруг входа:

- `ENABLE_SOCIAL_APPS_USER_REGISTRATION=true` — вход через провайдера создаёт
  пользователя, даже когда обычная регистрация закрыта;
- `SOCIAL_AUTH_BLOCK_PRIVATE_IPS=false` — разрешает discovery к IdP в LAN;
- администратором вход через Zitadel не делает: права выдаются учётке после
  первого входа, порядок — в `RUNBOOK.md`;
- `ENABLE_ORGANIZATION_CREATION=true` — организацию заводит любой вошедший.

## Подключение приложений

В проекте GlitchTip создать DSN вида:

```
https://<public-key>@glitchtip.example.com/<project-id>
```

и указать его в Sentry SDK приложения.

Первый вход и проверка — в `RUNBOOK.md`.

## Загрузка source maps

Карты исходников заливает `sentry-cli`, запущенный внутри кластера (Job в юните
`petri-nets` при синке приложения). GlitchTip сообщает клиенту абсолютный адрес
загрузки, собранный из `GLITCHTIP_URL`, то есть публичный `https://glitchtip.<домен>`;
из кластера этот адрес ведёт наружу и упирается в NetworkPolicy. Поэтому включён
`GLITCHTIP_CHUNK_UPLOAD_USE_RELATIVE_URL`: эндпоинт отдаёт относительный путь, и
клиент грузит чанки на тот хост, с которым сам пришёл. Для загрузки снаружи это
ничего не меняет — относительный путь работает и через публичный URL.

Токен загрузки — отдельный кред, выданный GlitchTip приложению
(`kv/glitchtip/@petri-nets/sourcemaps-token`, правило 3 ADR 0006). Скоупа
`project:write` достаточно для самих артефактов, но создание release требует
`project:releases`, поэтому у токена должны быть оба.
