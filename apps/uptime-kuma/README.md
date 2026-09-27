# Uptime Kuma

Uptime-мониторинг сервисов: дашборд статусов, метрики Prometheus, уведомления.

## Запуск

Разворачивается kustomize-набором из `apps/uptime-kuma/`:

```sh
kubectl apply -k apps/uptime-kuma/
```

`monitors.yaml` и `sync-monitors.ts` хранятся в исходном виде, а
`configMapGenerator` собирает из них ConfigMap `uptime-kuma-sync-files`
(имя получает hash-суффикс от содержимого), который монтируется в CronJob.
Ручная копия в `/storage` не нужна.

Завершить первоначальную настройку учётной записи по адресу
`https://kuma.example.com/`.

## Память

Node-процесс Kuma со временем раздувается до гигабайта и больше: кэш heartbeats
держится в памяти для websocket-клиентов, а V8 не возвращает освобождённую
память операционной системе. Поэтому задано
`NODE_OPTIONS=--max-old-space-size=512`: heap ограничен, RSS держится
примерно в два раза меньше прежнего. Если контейнер начнёт перезапускаться по
OOM, значение можно поднять.

## База данных

Kuma 2.x не использует SQLite: переменные `UPTIME_KUMA_DB_TYPE` не заданы, и
приложение поднимает **встроенную** MariaDB (`embedded-mariadb`) внутри пода с
данными в `/app/data/mariadb` на томе `uptime-kuma-data`. Сейчас там 36 МБ
полезных данных на 28 таблиц и 265 МБ каталога — разницу дают redo-логи и
служебное табличное пространство InnoDB.

Пока БД живёт в поде, её нечем бэкапить средствами MariaDB, а потеря тома уносит
мониторы и всю историю проверок. Поэтому БД выносится в отдельный кластер:

- `platform/mariadb/uptime-kuma-mariadb.instance.yaml` — MariaDB под
  mariadb-operator, одна реплика, 1 GiБ;
- `platform/mariadb/uptime-kuma-mariadb.databases.yaml` — база `kuma`,
  `cleanupPolicy: Skip`, чтобы опечатка в манифесте не удалила данные;
- `platform/mariadb/uptime-kuma-mariadb.users.yaml` — пользователь
  `uptime_kuma` и его права, пароль из Secret;
- `apps/uptime-kuma/k8s/vaultstaticsecret-mariadb.yaml` — два пути в Vault:
  `kv/uptime-kuma/db` (учётные данные приложения) и `kv/uptime-kuma/root`
  (root-пароль для оператора).

Почему одна реплика, а не три: кластер на Galera на одной ноде не даёт
отказоустойчивости — реплики всё равно жили бы на том же узле, а потеря ноды
убивает их все. Ценность перехода в выносе состояния из пода и в обычных
средствах бэкапа. Масштабирование до 3 реплик — одна строка, оператор
поднимет поды и сделает SST сам. При 2 репликах нельзя: кворум Galera требует
нечётного числа узлов, и выживший узел уходит в read-only, то есть вместо
простоя приложение получает ошибки записи.

### Перенос

1. Создать в Vault значения и применить политику:

   ```sh
   vault kv put kv/uptime-kuma/db DB_USERNAME=uptime_kuma DB_PASSWORD=...
   vault kv put kv/uptime-kuma/root INIT_UPTIME_KUMA_MARIADB_ROOT_PASSWORD=...
   cd terraform/vault && terraform apply
   ```

2. Применить кластер и секреты (Kuma на этом шаге не трогается):

   ```sh
   kubectl apply -f platform/mariadb/uptime-kuma-mariadb.instance.yaml
   kubectl apply -f platform/mariadb/uptime-kuma-mariadb.databases.yaml
   kubectl apply -f platform/mariadb/uptime-kuma-mariadb.users.yaml
   kubectl apply -f apps/uptime-kuma/k8s/vaultstaticsecret-mariadb.yaml
   ```

3. Перенести данные:

   ```sh
   apps/uptime-kuma/migrate-db.sh
   ```

   Скрипт снимает дамп со встроенной MariaDB через unix-сокет (аутентификация
   по сокету, пароль не нужен) и заливает его во внешний кластер, после чего
   сверяет набор таблиц. Kuma при этом продолжает работать: `--single-transaction`
   даёт согласованный снимок InnoDB без остановки. Повторный запуск безопасен —
   целевая база очищается перед заливкой.

4. Переключить Kuma на внешнюю базу: в `k8s/deployment.yaml` добавить
   `UPTIME_KUMA_DB_TYPE`, `UPTIME_KUMA_DB_HOSTNAME`, `UPTIME_KUMA_DB_PORT`,
   `UPTIME_KUMA_DB_NAME` и учётные данные из Secret `uptime-kuma-mariadb`, затем
   `kubectl apply -k apps/uptime-kuma/`. Переменные перекрывают
   `/app/data/db-config.json` (приоритет env над файлом, `server/setup-database.js`),
   поэтому Kuma перепишет конфигурацию сама.

5. Проверить в UI, что на месте все мониторы и status page, а `/metrics`
   отдаётся. Мониторы описаны в Terraform, поэтому после переподключения
   `terraform plan` должен остаться пустым.

6. Удалить старые данные с тома: каталоги `/app/data/mariadb` и `/app/data/run`.
   Сам PVC `uptime-kuma-data` не удаляется — в нём остаются `upload/`,
   `screenshots/` и `error.log`.

### Оговорка про пароль на диске

Kuma 2.x всегда записывает параметры подключения в `/app/data/db-config.json`
вместе с паролем, независимо от способа подачи: `UPTIME_KUMA_DB_PASSWORD` или
`UPTIME_KUMA_DB_PASSWORD_FILE`. Это устройство приложения, а не ошибка
конфигурации — обойти его нельзя. Пароль БД лежит на томе `longhorn-retain`
открытым текстом, поэтому его стоит выдавать отдельным значением с коротким
сроком жизни и ротировать вместе с доступом к Vault.

## Метрики

Kuma отдаёт Prometheus-метрики на `:80/metrics`. Доступ — по API-ключу
(Настройки → API Keys, без срока действия): ключ хранится как
`UPTIME_KUMA_METRICS_API_KEY`, netdata скрейпит их как цель `uptime-kuma`
(см. `apps/netdata/README.md`). После добавления первого API-ключа basic auth на
`/metrics` отключается навсегда.

## Декларативные мониторы

Желаемое состояние мониторов перешло в Terraform: `terraform/uptime-kuma/`.
Gatus (`apps/gatus/config/config.yaml`) — источник правды, Kuma зеркалит его там,
где это возможно.

Механизм ниже пока не удалён и больше не является источником правды. **CronJob
`sync-monitors` запускать нельзя**: он перепишет мониторы в состояние из
`monitors.yaml` и разойдётся с Terraform. Его снос — отдельная задача.

Применение `sync-monitors.ts` идемпотентно: создаются отсутствующие мониторы и
обновляются изменённые. Существующие мониторы сопоставляются по имени. Мониторы,
удалённые из `monitors.yaml`, автоматически не удаляются, чтобы случайно не
потерять ручную настройку и историю проверок.

После изменения конфигурацию нужно применить повторно. Для добавления нового
типа сначала расширить проверку входных данных в `sync-monitors.ts`.
