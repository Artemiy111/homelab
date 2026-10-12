# Authentik: эксплуатация

## Первый запуск

Откройте `https://auth.example.com/if/flow/initial-setup/` и задайте
пароль встроенному администратору `akadmin`. Не меняйте
`AUTHENTIK_SECRET_KEY`: это приведёт к завершению активных сессий.

## Вход только по passkey

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
