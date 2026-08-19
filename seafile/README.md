# Seafile

Seafile — файловое облако для синхронизации и обмена файлами. Сервис доступен
только в локальной сети и через Tailscale по адресу
`https://seafile.example.com/`. TLS завершается в Traefik; порты Seafile и
MariaDB на хост не публикуются.

## Состав

- `seafile` — официальный community Docker-образ Seafile 13;
- `db` — MariaDB с базами Seafile, Seahub и CCNet;
- `memcached` — кеш Seafile;
- `backup-db` — одноразовый дамп всех баз MariaDB перед Restic backup.

Постоянные данные находятся в `$APPS_STORAGE_PATH/seafile`:

- `shared` — конфигурация, библиотеки, загруженные файлы и журналы Seafile;
- `mysql` — MariaDB;
- `backups` — локальные дампы базы.

Каталог `$APPS_STORAGE_PATH` уже входит в общий Restic backup. Локальная копия
на том же диске не защищает от его поломки или потери.

## Первый запуск

Инициализация создаёт каталоги и локальный `seafile/.env` с правами `0600`.
Пароли генерируются только при создании файла и не перезаписываются:

```sh
cd /home/artlab/projects/homelab
bash seafile/init.sh
cd seafile
docker compose config --quiet
docker compose up -d
docker compose ps
```

Начальная учётная запись берётся из `INIT_SEAFILE_ADMIN_EMAIL` и
`INIT_SEAFILE_ADMIN_PASSWORD` в `seafile/.env`. Она создаётся только при первом
запуске на пустом `$APPS_STORAGE_PATH/seafile/shared`.

После входа смените пароль и создайте отдельную учётную запись администратора
для повседневной работы. Не публикуйте содержимое `.env` и не добавляйте его в
Git.

## Проверка

```sh
docker compose ps
docker compose exec seafile curl -fsS http://127.0.0.1/api2/ping
curl --resolve seafile.example.com:443:192.0.2.10 \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://seafile.example.com/api2/ping
```

Ожидаются healthy-контейнер `db`, работающий `seafile` и ответ `pong` из
внутренней проверки. Внешняя проверка должна вернуть HTTP `200`.

## Резервное копирование

Перед общим Restic backup создайте согласованный дамп MariaDB:

```sh
docker compose --profile tools run --rm backup-db
ls -lh ${APPS_STORAGE_PATH:-/storage/apps}/seafile/backups/seafile.sql
```

Дамп содержит базы Seafile, Seahub и CCNet. Восстановление сначала выполняйте
в изолированный экземпляр MariaDB, не поверх рабочих данных.

## Обновление

Сначала создайте дамп базы и Restic snapshot. Версию образа меняйте в `init.sh`,
`.env.example` и серверном `.env` согласованно; существующий `.env` `init.sh`
не перезаписывает. Перед переходом между major-версиями проверьте официальные
[инструкции Seafile](https://manual.seafile.com/latest/setup/overview/).

```sh
docker compose pull
docker compose up -d
docker compose ps
```
