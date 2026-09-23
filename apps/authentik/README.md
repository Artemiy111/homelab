# Authentik

Authentik — тестовый identity provider. 
URL: `https://auth.example.com/`

Разворачивается манифестами в apps/authentik/k8s/.

## Первый запуск

Секреты сервиса — секретный ключ Authentik, пароль PostgreSQL, CIDR Traefik —
хранятся в `apps/authentik/secrets.enc.env` с правами `0600`.

Откройте `https://auth.example.com/if/flow/initial-setup/` и задайте
пароль встроенному администратору `akadmin`. Не меняйте
`AUTHENTIK_SECRET_KEY`: это приведёт к завершению активных сессий.

## Вход только по passkey

Authentik поддерживает passwordless-аутентификацию через WebAuthn; правило
применяется одинаково к обычным пользователям и `akadmin`. Не включайте её до
регистрации хотя бы двух passkey для `akadmin` на разных устройствах.

1. В админ-интерфейсе создайте WebAuthn Authenticator setup stage с
   `Resident key requirement: Required` и зарегистрируйте passkey через
   пользовательские настройки `akadmin`.
2. Создайте отдельный Authentication flow: WebAuthn Authenticator Validation
   stage (device class `webauthn`, `Not configured action: Deny`) → User Login
   stage.
3. Назначьте этот flow как default authentication flow и удалите либо отвяжите
   Password stage из всех доступных authentication flows. Не оставляйте
   passwordless flow только ссылкой на обычной форме входа: обычный flow должен
   быть недоступен, иначе пароль останется альтернативой.
4. В отдельном браузерном профиле проверьте вход по passkey, и лишь затем
   завершите текущую сессию администратора.

У этого режима нет безопасного password fallback. Храните минимум две passkey
на независимых устройствах и заранее определите аварийный порядок
восстановления доступа.

## Хранилище

База — PostgreSQL в общем кластере CNPG `shared` (namespace `databases`,
эндпоинт `shared-rw.databases.svc.cluster.local:5432`). Роль `authentik`, база
`authentik` и NetworkPolicy объявлены в `platform/cnpg/`; пароль роль берёт из
Secret'а `authentik-db-auth`, приложение — из своего Secret'а `authentik`
(ключ `AUTHENTIK_POSTGRESQL_PASSWORD`), поэтому менялся только хост. Данные
перенесены из локального `authentik-postgresql` дампом, старый Deployment снят.

## Проверка

```sh
curl --resolve auth.example.com:443:<node1-ip> \
  -fsS https://auth.example.com/-/health/ready/
```

Endpoint `/-/health/ready/` возвращает `200`, когда Authentik может подключиться
к PostgreSQL.

## Обновление

Перед обновлением создайте dump PostgreSQL и прочитайте release notes.
Обновления мажорных релизов выполняйте последовательно.
