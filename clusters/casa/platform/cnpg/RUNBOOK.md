# CloudNativePG: эксплуатация

## Как расширить том

Смена `spec.storage.size` **не прокатывается на PVC автоматически**: для
одноинстансного кластера оператор только сообщает
`PostgreSQL cannot proceed until the PVC group is enlarged`, а сам PVC не
трогает (реплики он пересоздаёт, primary — нет). Порядок из трёх шагов:

```sh
# 1. Увеличить размер в Cluster (и применить). Оператор увидит нехватку места.
kubectl apply -f clusters/casa/platform/cnpg/<cluster>.cluster.yaml

# 2. Увеличить сам PVC: Longhorn расширяет том на ходу.
kubectl -n <ns> patch pvc <cluster>-1 --type=merge \
  -p '{"spec":{"resources":{"requests":{"storage":"3Gi"}}}}'

# 3. Разорвать цикл FS-resize: файловая система расширяется при монтировании,
#    а под в CrashLoopBackOff смонтировать не может.
kubectl -n <ns> delete pod <cluster>-1
```

После второго шага PVC остаётся в `FileSystemResizePending`, а том Longhorn уже
нового размера. Удаление пода заставляет его перемонтировать том, FS
расширяется, PVC показывает новый размер, кластер поднимается.

## Первый запуск руками: test18

Начать стоит не с боевых кластеров, а с одноразового `test18`. Заодно это
проверка cross-namespace: кластер в `databases`, а секрет роли — там же, где и
кластер. Пароль лежит открытым текстом в `test18.secret.yaml` — он заведомо
тестовый, для боевых баз так нельзя.

```sh
# 0. Namespace'ы: databases, zitadel, immich, dawarich.
#    Их объявляет clusters/casa/platform/namespaces/, а не этот каталог:
#    каталог cnpg под Argo не стоит, и объявления из ручного apply в git
#    не доходили. Если Argo ещё не поднят — применяй руками:
kubectl apply -f clusters/casa/platform/namespaces/manifests/namespaces.yaml

# 1. Оператор: в Argo приложение и sync, либо
kubectl apply -f clusters/casa/platform/cloudnative-pg/app.yaml
argocd app sync cloudnative-pg
kubectl -n cnpg-system get pods -w

# 2. Secret раньше кластера: из него берётся пароль роли test18
kubectl apply -f clusters/casa/platform/cnpg/test18.secret.yaml
kubectl apply -f clusters/casa/platform/cnpg/test18.cluster.yaml
kubectl -n databases get cluster test18 -w   # ждём Cluster in healthy state

# 3. База — только когда кластер healthy (см. «Грабли»)
kubectl apply -f clusters/casa/platform/cnpg/test18.databases.yaml
kubectl -n databases get database testdb18 -o wide
```

Что посмотреть, пока кластер жив:

```sh
# Оператор сам создал StatefulSet, Service'ы, PVC и секреты
kubectl -n databases get statefulset,pod,svc,pvc,secret | grep test18

# Сервисы: -rw (primary), -ro (реплики), -r (любой)
kubectl -n databases get svc test18-rw test18-ro test18-r

# Роли и базы: служебная app/app — не наша, рабочая testdb18/test18
kubectl -n databases exec -it test18-1 -c postgres -- \
  psql -U postgres -d postgres -c '\l'
kubectl -n databases exec -it test18-1 -c postgres -- \
  psql -U postgres -d postgres \
  -c "select rolname, rolcanlogin, rolsuper from pg_roles where rolname not like 'pg\_%'"

# Подключение рабочей ролью (хост — <cluster>-rw)
kubectl -n databases exec -it test18-1 -c postgres -- \
  env PGPASSWORD=test-password psql -h 127.0.0.1 -U test18 -d testdb18 -c '\l'
```

Убирать за собой:

```sh
kubectl delete -f clusters/casa/platform/cnpg/test18.databases.yaml   # базу удаляем отдельно
kubectl delete -f clusters/casa/platform/cnpg/test18.cluster.yaml
kubectl delete -f clusters/casa/platform/cnpg/test18.secret.yaml
```

## Предусловия

1. Оператор установлен и CRD есть: `kubectl -n cnpg-system get deploy`.
2. Namespace'ы созданы — приложение `namespaces` в `Synced`, либо
   `kubectl apply -f clusters/casa/platform/namespaces/manifests/namespaces.yaml`.
3. В Vault заведены пароли ролей, VSO синхронизирует их в basic-auth Secret'ы
   (`VaultStaticSecret`), **в namespace своего кластера**:
   - `databases`: `nextcloud-db-auth`, `forgejo-db-auth`, `element-db-auth`
     (роль `synapse`), `paperless-db-auth`, `glitchtip-db-auth`,
     `infisical-db-auth`, `postgres-db-auth` (роль `playground`), `gatus-db-auth`,
     `grafana-db-auth`, `openwebui-db-auth`, `authentik-db-auth`, `sure-db-auth` —
     `db-auth.vaultstaticsecrets.yaml`;
   - `zitadel`: `zitadel-db-auth` — в юните `clusters/casa/apps/zitadel/`;
   - `immich`: `immich-db-auth` — в юните `clusters/casa/apps/immich/`;
   - `dawarich`: `dawarich-db-auth` — в юните `clusters/casa/apps/dawarich/`.

   Пароли переиспользованы из Secret'ов сервисов, чтобы при миграции менялся
   только хост.

Без Secret'ов кластер поднимется, а роли и базы останутся неотреконсиленными —
это видно в `kubectl -n <ns> get cluster <name> -o yaml` и в статусе
`Database`-объектов.

## Установка

Порядок важен: namespace'ы → кластеры → дождаться `healthy` → базы. Иначе
`Database`-объекты один раз увидят отсутствующий кластер и залипнут в
`applied: false` (см. «Грабли»).

```sh
kubectl apply -f clusters/casa/platform/namespaces/manifests/namespaces.yaml
kubectl apply -f clusters/casa/platform/cnpg/db-auth.vaultauth.yaml           # SA и VaultAuth ролей
kubectl apply -f clusters/casa/platform/cnpg/db-auth.vaultstaticsecrets.yaml  # пароли ролей из Vault
kubectl apply -f clusters/casa/platform/cloudnative-pg/app.yaml          # оператор (+ sync в Argo)
kubectl -n cnpg-system get pods -w

kubectl apply -f clusters/casa/platform/cnpg/*.cluster.yaml
kubectl get cluster -A -w                                # ждём healthy

kubectl apply -f clusters/casa/platform/cnpg/*.databases.yaml
kubectl get cluster,database -A
```

## Проверка

```sh
# Кластеры поднялись и готовы
kubectl get cluster -A
# Роли и базы отреконсилены
kubectl get database -A
# Под с базой и его контейнеры
kubectl -n databases exec -it shared-1 -c postgres -- psql -U postgres -c '\l'
# Расширения Immich на месте (должны быть vector, vchord, earthdistance, cube)
kubectl -n immich exec -it immich-1 -c postgres -- psql -U postgres -d immich -c '\dx'
# vchord загружен в postmaster
kubectl -n immich exec -it immich-1 -c postgres -- \
  psql -U postgres -c 'show shared_preload_libraries'
# Метрики на месте (порт 9187, отдаёт instance manager)
kubectl -n databases exec shared-1 -c postgres -- \
  curl -s localhost:9187/metrics | grep '^cnpg_collector_up'
```

## Миграция данных

Для пустого кластера — ничего не делать, базы создадутся пустыми. Для переноса
данных есть два пути, и они взаимоисключающие: `bootstrap` задаётся один раз,
при создании кластера.

1. **Логический импорт при bootstrap** — `spec.bootstrap.initdb.import` с
   `externalClusters` (источником) и `type: microservice`: оператор поднимет
   кластер и зальёт базы через `pg_dump`/`pg_restore`. Требует, чтобы источник
   был доступен по сети, а пароль — в Secret'е `kubernetes.io/basic-auth`.
2. **Перенос руками** — создать кластер пустым, затем
   `pg_dump -Fc` из источника → `pg_restore` в `<cluster>-rw`. Проще откатывать
   по шагам и не смешивать «создание кластера» и «перенос данных».

Порядок на одну базу (не на все сразу): дамп → рестор → переключить сервис на
`<cluster>-rw` (и на нового пользователя, если он изменился) → убедиться, что
живо → удалить старый `*-db` Deployment. Пока источник жив, откат бесплатный.

## Мажорный апгрейд

Апгрейд делается на месте сменой `imageName` на следующий мажор: оператор гасит
кластер, прогоняет `pg_upgrade --link` на том же PVC и поднимает обратно. Имя
кластера и строки подключения у сервисов при этом не меняются — именно ради
этого имя не содержит версии (`docs/adr/0003`).

Условия: тот же дистрибутив ОС (`trixie` → `trixie`), совместимые расширения в
целевом образе, обязательный бэкап до. После апгрейда — новый base backup: PITR
не пересекает мажоры. Кластеры с расширениями (`immich-db`, `dawarich-db`) ждут
сборки расширения под новый мажор независимо и не задерживают `shared`.

## Грабли

- **Статус `Database` переживает пересоздание кластера.** Если `Database` уже
  существует, а `Cluster` удалить и создать заново, оператор один раз увидит
  `cluster resource has been deleted, skipping reconciliation`, оставит
  `status.applied: false` и сам больше не пошевелится — база не создастся.
  Лечение: удалить и применить `Database` заново (или разбудить его правкой).
  Поэтому базы и вынесены в отдельные файлы и применяются **после** того, как
  кластер стал `healthy`.
- **`bootstrap` применяется только при создании.** Менять `initdb`-часть спеки
  у живого кластера бессмысленно — нужен пересоздатель.
- **Extension-image и `shared_preload_libraries` не менять одновременно.**
  Оператор предупреждает: сначала докати под с новым образом расширения, потом
  правь GUC. И любое добавление или обновление extension-image перезапускает
  поды всего кластера.
