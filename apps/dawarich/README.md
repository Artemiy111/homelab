# Dawarich

Dawarich хранит и визуализирует историю местоположений.
URL: `https://dawarich.example.com/`

## Первый запуск

Из корня репозитория:

```sh
bash scripts/bootstrap-platform.sh dawarich
```

На пустой базе встроенный seed Dawarich создаёт администратора
`demo@dawarich.app` с паролем `safepassword`. Сразу после первого входа измените
email и пароль в настройках аккаунта.

## Проверка

```sh
docker compose ps
docker compose exec app wget --header='X-Forwarded-Proto: https' -qO- \
  http://127.0.0.1:3000/api/v1/health
curl --resolve dawarich.example.com:443:192.0.2.10 \
  -fsS https://dawarich.example.com/api/v1/health
```

Health endpoint должен вернуть JSON со `"status":"ok"`.

## Резервное копирование

Для согласованной копии остановите процессы, меняющие данные, создайте дамп
PostgreSQL, затем запустите общий Restic backup:

```sh
cd /home/artlab/projects/homelab/dawarich
docker compose stop app sidekiq
docker compose --profile tools run --rm backup-db
cd ../restic
docker compose run --rm backup
cd ../dawarich
docker compose start app sidekiq
```

Дамп сохраняется в `$APPS_STORAGE_PATH/dawarich/backups/dawarich.dump`. Restic
repository находится на том же физическом диске и не защищает от его поломки
или потери. Исходные файлы импорта не следует удалять после загрузки в Dawarich.

## Обновление

Перед обновлением создайте согласованный backup, прочитайте release notes и
измените `DAWARICH_VERSION` в `config.env`.
Затем выполните:

```sh
docker compose pull
docker compose up -d
docker compose ps
```
