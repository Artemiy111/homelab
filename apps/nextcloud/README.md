# Nextcloud

Файловое облако доступно только в локальной сети и через Tailscale по адресу
`https://nextcloud.example.com/`. Traefik завершает TLS; порты Nextcloud,
PostgreSQL и Redis на хост не публикуются.

## Состав

- `app` — Nextcloud с Apache;
- `db` — PostgreSQL в общем кластере CNPG `shared` (подробнее «База»);
- `redis` — кеш, сессии и блокировки файлов;
- `cron` — рекомендуемый Nextcloud планировщик фоновых заданий;
- `backup-db` — одноразовый дамп PostgreSQL.

Постоянное состояние хранится в томе сервиса. Каталог `html` разделяется
контейнерами `app` и `cron`.

## База

PostgreSQL в общем кластере CNPG `shared` (namespace `databases`, эндпоинт
`shared-rw.databases.svc.cluster.local:5432`). Роль `nextcloud`, база `nextcloud`
и NetworkPolicy объявлены в `platform/cnpg/`; пароль роль берёт из Secret'а
`nextcloud-db-auth`, а приложение — из своего Secret'а `nextcloud-db` (ключ
`password`). Значение одно: путь `kv/nextcloud/db`.

Реальные параметры подключения живут в `config.php` внутри тома `html`, а не в
env: переменная `POSTGRES_HOST` учитывается только при первой установке. Поэтому
при переезде хост, пользователь и пароль БД меняются через
`occ config:system:set dbhost/dbuser/dbpassword`, а не правкой Deployment'ов.
Данные перенесены из локального `nextcloud-db` дампом (`pg_dump`/`pg_restore`);
пользователь БД сменился с установочного `oc_admin` на роль `nextcloud`. Старый
DB-Deployment и его hostPath-каталог удалены.

## Первый запуск

Разворачивается манифестами в apps/nextcloud/k8s/.

Независимые пароли PostgreSQL и администратора задаются в Vault:
`kv/nextcloud/@nextcloud/db` (выдаёт CNPG) и `kv/nextcloud/admin`
(`NEXTCLOUD_ADMIN_USER` / `NEXTCLOUD_ADMIN_PASSWORD`). Узнать первичные
реквизиты можно в UI или вычитав их из Kubernetes Secret.

После входа создать обычную пользовательскую учётную запись. Начальную
административную учётную запись не использовать для повседневной работы.

## Проверка

```sh
curl --resolve nextcloud.example.com:443:<node1-ip> \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://nextcloud.example.com/status.php
```

Ожидается HTTP `200`.

## Фоновые задания и административные предупреждения

Контейнер `cron` запускает `cron.php` каждые пять минут. После первого запуска
режим фоновых заданий автоматически переключится на `Cron`. Предупреждения
проверять в `Administration settings → Overview`.

Окно тяжёлых ежедневных заданий — 00:00 UTC, телефонный регион — российский
(`default_phone_region=RU`).

SMTP намеренно не задаётся в конфигурации: его следует настроить в
административном интерфейсе после выбора почтового провайдера.

## Резервное копирование

Одноразовое задание `backup-db` создаёт атомарно заменяемый дамп базы.
Дамп, пользовательские файлы, конфигурация и приложения находятся в томе
состояния Nextcloud.

## Обновление

Сначала создать дамп базы. Обновления maintenance-релизов
делать изменением фиксированного тега обоих образов Nextcloud в манифестах.
Major-версии обновлять последовательно, не пропуская версии.
