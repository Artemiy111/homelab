# Nextcloud

Файловое облако доступно только в локальной сети и через Tailscale по адресу
`https://nextcloud.example.com/`. Traefik завершает TLS; порты Nextcloud,
PostgreSQL и Redis на хост не публикуются.

## Состав

- `app` — Nextcloud с Apache;
- `db` — PostgreSQL;
- `redis` — кеш, сессии и блокировки файлов;
- `cron` — рекомендуемый Nextcloud планировщик фоновых заданий;
- `backup-db` — одноразовый дамп PostgreSQL перед Restic backup.

Постоянное состояние находится в `$APPS_STORAGE_PATH/nextcloud`. Каталог `html`
разделяется контейнерами `app` и `cron`; SELinux для него использует shared-label
`z`. Остальные bind mounts используют private-label `Z`.

## Первый запуск

```sh
bash scripts/bootstrap-platform.sh nextcloud
```

`init.sh` создаёт каталоги состояния, генерирует независимые пароли PostgreSQL
и администратора, записывает их только в `apps/nextcloud/secrets.enc.env` с правами `0600` и не
перезаписывает существующий файл. Узнать первичные реквизиты можно непосредственно
в терминале сервера:

```sh
sops -d apps/nextcloud/secrets.enc.env | sed -n '/^NEXTCLOUD_ADMIN_\(USER\|PASSWORD\)=/p'
```

После входа создать обычную пользовательскую учётную запись. Начальную
административную учётную запись не использовать для повседневной работы.

## Проверка

```sh
docker compose ps
docker compose exec --user www-data app php occ status
docker compose exec --user www-data app php occ config:system:get trusted_proxies
curl --resolve nextcloud.example.com:443:192.0.2.10 \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://nextcloud.example.com/status.php
```

Ожидаются healthy-контейнеры, `installed: true` и HTTP `200`.

## Фоновые задания и административные предупреждения

Контейнер `cron` запускает `cron.php` каждые пять минут. После первого запуска
режим фоновых заданий автоматически переключится на `Cron`. Предупреждения
проверять в `Administration settings → Overview`.

Настроить окно тяжёлых ежедневных заданий на 00:00 UTC и российский телефонный
регион:

```sh
docker compose exec --user www-data app php occ config:system:set \
  maintenance_window_start --type=integer --value=0
docker compose exec --user www-data app php occ config:system:set \
  default_phone_region --value=RU
```

SMTP намеренно не задаётся в Compose: его следует настроить в административном
интерфейсе после выбора почтового провайдера.

## Резервное копирование

Перед общим Restic backup создать атомарно заменяемый дамп базы:

```sh
docker compose --profile tools run --rm backup-db
ls -lh ${APPS_STORAGE_PATH:-/storage/apps}/nextcloud/backups/nextcloud.dump
```

После этого запускать `restic/backup`. Restic уже читает весь `$APPS_STORAGE_PATH`,
поэтому в снимок попадут дамп, пользовательские файлы, конфигурация и приложения.
Restic repository находится на том же физическом диске и не защищает от его
поломки или потери.

## Обновление

Сначала создать дамп базы и Restic snapshot. Обновления maintenance-релизов
делать изменением фиксированного тега обоих образов Nextcloud в `compose.yaml`.
Major-версии обновлять последовательно, не пропуская версии.

```sh
docker compose pull
docker compose up -d
docker compose exec --user www-data app php occ status
```
