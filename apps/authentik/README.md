# Authentik

Authentik — тестовый identity provider. 
URL: `https://auth.example.com/`

## Первый запуск

Из корня репозитория:

```sh
bash scripts/bootstrap-platform.sh authentik
```

`init.sh` создаст каталоги (включая `backups`), секретный ключ Authentik, пароль PostgreSQL, CIDR Traefik и `apps/authentik/secrets.enc.env` с
правами `0600`.

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

## Проверка

```sh
docker compose ps
curl --resolve auth.example.com:443:192.0.2.10 \
  -fsS https://auth.example.com/-/health/ready/
docker logs --since=5m authentik-server 2>&1
docker logs --since=5m authentik-worker 2>&1
```

Endpoint `/-/health/ready/` возвращает `200`, когда Authentik может подключиться
к PostgreSQL. После первого запуска добавьте монитор в Uptime Kuma:

```sh
cd /home/artlab/projects/homelab/uptime-kuma
docker compose --profile tools run --rm configure
```

## Резервное копирование

Перед общим Restic backup создайте согласованный dump PostgreSQL:

```sh
cd /home/artlab/projects/homelab/authentik
docker compose --profile tools run --rm backup-db
```

Restic сохраняет `$APPS_STORAGE_PATH/authentik`; секреты — зашифрованными в Git. Для восстановления сначала восстановите snapshot в отдельный
каталог и проверьте содержимое; не заменяйте работающие данные без отдельного
backup.

## Обновление

Перед обновлением создайте dump PostgreSQL и прочитайте release notes. Версия
образа закреплена в `compose.yaml`; обновления мажорных релизов выполняйте
последовательно.

```sh
docker compose pull
docker compose up -d
docker compose ps
```
