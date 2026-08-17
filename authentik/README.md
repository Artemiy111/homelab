# Authentik

Authentik — отдельный identity provider, работающий параллельно с Pocket ID.
Интерфейс доступен только через Traefik по адресу
`https://auth.example.net/`; порты контейнеров на хосте не публикуются.

Данные приложения хранятся в `$APPS_STORAGE_PATH/authentik/data`, PostgreSQL — в
`$APPS_STORAGE_PATH/authentik/postgresql`. Контейнер worker намеренно не получает
Docker socket: при необходимости proxy outposts нужно разворачивать вручную.

## Первый запуск

После доставки изменений на сервер выполните bootstrap. Он создаст каталоги,
секретный ключ Authentik, пароль PostgreSQL, CIDR Traefik и `authentik/.env` с
правами `0600`.

```sh
cd /home/artlab/projects/homelab
bash scripts/bootstrap-platform.sh
cd authentik
docker compose config --quiet
docker compose pull
docker compose up -d
docker compose ps
```

Откройте `https://auth.example.net/if/flow/initial-setup/` и задайте
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
curl --resolve auth.example.net:443:192.0.2.10 \
  -fsS https://auth.example.net/-/health/ready/
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

Restic сохраняет `$APPS_STORAGE_PATH/authentik` и локальный `authentik/.env` из
рабочей копии. Для восстановления сначала восстановите snapshot в отдельный
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
