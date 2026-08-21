# Seafile

Seafile — файловое облако для синхронизации и обмена файлами. Сервис доступен
только в локальной сети и через Tailscale по адресу
`https://seafile.example.com/`. TLS завершается в Traefik; порты Seafile и
MariaDB на хост не публикуются.

## Состав

- `seafile` — официальный community Docker-образ Seafile 13;
- `db` — MariaDB с базами Seafile, Seahub и CCNet;
- `redis` — кэш Seafile и служебные очереди;
- `onlyoffice` — ONLYOFFICE Docs Community Edition для редактирования DOCX,
  XLSX и других офисных форматов;
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
bash ../seafile/init.sh
docker compose restart seafile
docker compose ps
```

Второй запуск `init.sh` выполняется уже после создания контейнером файла
`shared/seafile/conf/seahub_settings.py`: он подключает к нему файл настроек
редактора `seahub_onlyoffice.py`. При последующих обновлениях достаточно
выполнить `init.sh` перед перезапуском стека.

Начальная учётная запись берётся из `INIT_SEAFILE_ADMIN_EMAIL` и
`INIT_SEAFILE_ADMIN_PASSWORD` в `seafile/.env`. Она создаётся только при первом
запуске на пустом `$APPS_STORAGE_PATH/seafile/shared`.

## Встроенный редактор документов

В стек включён ONLYOFFICE Docs Community Edition. Он добавляет редактирование
`docx`, `xlsx`, `pptx`, `csv`, `pdf` и совместимых форматов непосредственно из
интерфейса Seafile. Для браузера API редактора доступен через Traefik по
`https://onlyoffice.example.com/`; отдельный порт на хост не публикуется.

`init.sh` генерирует общий JWT-секрет для Seafile и ONLYOFFICE. Существующий
`.env` автоматически дополняется настройками редактора без замены имеющихся
секретов. Настройки редактора для Seahub живут в отслеживаемом файле
`seahub_onlyoffice.py`: он примонтирован в контейнер read-only и подключается
из `seahub_settings.py`, а значения берёт из окружения контейнера. Seahub
читает настройки один раз при старте воркера, поэтому после изменения
`seahub_onlyoffice.py` или переменных `ONLYOFFICE_*` в `.env` выполните
`docker compose restart seafile` — иначе редактор покажет «Загрузка
не удалась». ONLYOFFICE разрешено обращаться к приватному адресу Seafile,
потому что сервисы работают только во внутренней сети homelab; внешний доступ
к ним по-прежнему ограничен DNS/Tailscale и Traefik. После обновления запустите:

```sh
docker compose pull onlyoffice seafile
docker compose up -d
docker compose ps
```

Проверка редактора:

```sh
docker compose exec onlyoffice curl -fsS http://127.0.0.1/healthcheck
curl --resolve onlyoffice.example.com:443:192.0.2.10 \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://onlyoffice.example.com/web-apps/apps/api/documents/api.js
```

Ожидаются `true` из внутренней проверки и HTTP `200` для API JavaScript.
Затем создайте или загрузите тестовые `.docx` и `.xlsx`, откройте их в Seafile,
измените содержимое и закройте редактор — Seafile сохранит изменения через
защищённый callback. Не меняйте `ONLYOFFICE_JWT_SECRET` на работающей установке
без планового перезапуска обоих контейнеров.

### «Загрузка не удалась» в редакторе

Если редактор открывается, но документ не загружается, проверьте, какую схему
видит DocumentServer на websocket-соединениях. Traefik не выставляет
`X-Forwarded-Proto` на websocket-upgrade запросах; из-за этого DocumentServer
строит ссылку на документ с `http://`, и браузер блокирует её как mixed
content. В `compose.yaml` для этого добавлена middleware
`onlyoffice-xfp` (принудительно `X-Forwarded-Proto: https`) — не удаляйте её.
Проверить схему можно в DEBUG-логе документсервера:

```sh
docker compose exec onlyoffice grep -a getBaseUrlByConnection \
  /var/log/onlyoffice/documentserver/docservice/out.log | tail -1
```

Ожидается `x-forwarded-proto=https`.

После входа смените пароль и создайте отдельную учётную запись администратора
для повседневной работы. Не публикуйте содержимое `.env` и не добавляйте его в
Git.

## Проверка

```sh
docker compose ps
docker compose exec seafile curl -fsS http://127.0.0.1/api2/ping/
curl --resolve seafile.example.com:443:192.0.2.10 \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://seafile.example.com/api2/ping/
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
