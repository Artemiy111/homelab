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

### Переключение на внешнюю базу

Переноса данных нет: база внешняя наполняется заново, мониторы и история
проверок создаются с нуля. Порядку важно — Kuma стартует на пустой базе раньше,
чем Terraform успеет создать мониторы.

1. Применить кластер и секреты:

   ```sh
   kubectl apply -f platform/mariadb/uptime-kuma-mariadb.instance.yaml
   kubectl apply -f platform/mariadb/uptime-kuma-mariadb.databases.yaml
   kubectl apply -f platform/mariadb/uptime-kuma-mariadb.users.yaml
   kubectl apply -f apps/uptime-kuma/k8s/vaultstaticsecret-mariadb.yaml
   ```

2. Дождаться готовности кластера и синхронизации секретов:

   ```sh
   kubectl -n uptime-kuma get mariadb,pods
   kubectl -n uptime-kuma annotate vaultstaticsecret uptime-kuma-mariadb \
     vso.secrets.hashicorp.com/force-sync="$(date +%s)" --overwrite
   ```

3. Переключить Kuma: остановить под, удалить старый том вместе с данными
   встроенной MariaDB и применить kustomization — PVC пересоздастся пустым,
   а Deployment получит `UPTIME_KUMA_DB_*`:

   ```sh
   kubectl -n uptime-kuma scale deploy/uptime-kuma --replicas=0
   kubectl -n uptime-kuma delete pvc uptime-kuma-data
   # Longhorn-том после удаления PVC остаётся сиротой: убрать и его.
   kubectl -n longhorn-system delete volume <том из шага ниже>
   kubectl apply -k apps/uptime-kuma/
   kubectl -n uptime-kuma get pods -w
   ```

   Проверить, что Kuma поднялся на внешней базе:

   ```sh
   kubectl -n uptime-kuma logs deploy/uptime-kuma | grep -i "Database Type"
   ```

   В логе должно быть `Database Type: mariadb`. Если осталось `sqlite` или
   `embedded-mariadb` — секреты не синхронизировались, и Kuma упала бы на
   отсутствии пароля, либо вернулась к встроенной БД.

4. Создать мониторы:

   ```sh
   cd terraform/uptime-kuma
   terraform apply
   ```

   Мониторы, теги, status page, прокси и настройки создаются из
   `terraform/uptime-kuma/`. Импортировать нечего: база пустая, поэтому
   `imports.tf` в модуле нет.

5. Проверить в UI, что все 62 монитора на месте, а `/metrics` отдаётся.

### Ключ метрик после перезапуска

Ключ API для `/metrics` хранится в базе, поэтому после её пересоздания он
исчезает, а basic auth на `/metrics` включается обратно. Нужен новый ключ в
UI (Настройки → API Keys, без срока действия) и новое значение в Vault по пути
`kv/uptime-kuma/@monitoring/uptime-kuma-metrics-api-key` — его читает vmagent
(`apps/victoria-metrics/k8s/vmagent.deployment.yaml`). После этого перезапустить
vmagent, иначе он продолжит скрейпить со старым ключом.

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
