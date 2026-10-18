# CloudNativePG: эксплуатация

## Как расширить том

Смена `spec.storage.size` **не прокатывается на PVC автоматически**: для
одноинстансного кластера оператор только сообщает
`PostgreSQL cannot proceed until the PVC group is enlarged`, а сам PVC не
трогает (реплики он пересоздаёт, primary — нет). Порядок из трёх шагов:

```sh
# 1. Увеличить размер в Cluster: правка доезжает приложением владельца.
#    Общий кластер — platform/cnpg (приложение cnpg), выделенный — юнит сервиса
#    (apps/<сервис>, приложение <сервис>).
$EDITOR clusters/casa/platform/cnpg/manifests/shared.cluster.yaml
git commit -m "..." && git push
argocd app sync cnpg

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

## Предусловия

1. Оператор установлен и CRD есть: `kubectl -n cnpg-system get deploy`.
2. Namespace'ы созданы — их объявляют юниты-владельцы: `databases` в
   `clusters/casa/platform/cnpg/manifests/namespace.yaml`, `cnpg-system` — в
   `clusters/casa/platform/cloudnative-pg/manifests/namespace.yaml`.
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

Порядок задан волнами: оператор и его namespace (10) → юнит `cnpg` (30), внутри
него секреты ролей (0) и кластер `shared` (10), дождаться `healthy` → базы
(20). Иначе `Database`-объекты один раз увидят отсутствующий кластер и залипнут
в `applied: false` (см. «Грабли»).

Штатный путь — Argo: оба приложения применяет root, порядок держат волны.

```sh
argocd app get cloudnative-pg   # оператор
argocd app get cnpg             # секреты ролей, кластеры, базы
kubectl get cluster,database -A
```

Поднять, когда Argo ещё не работает:

```sh
kubectl apply -f clusters/casa/platform/cloudnative-pg/manifests/namespace.yaml   # cnpg-system
kubectl apply -f clusters/casa/platform/cnpg/manifests/namespace.yaml            # databases
kubectl apply -f clusters/casa/platform/cloudnative-pg/app.yaml          # оператор
kubectl -n cnpg-system get pods -w

kubectl apply -f clusters/casa/platform/cnpg/manifests/db-auth.vaultauth.yaml           # SA и VaultAuth ролей
kubectl apply -f clusters/casa/platform/cnpg/manifests/db-auth.vaultstaticsecrets.yaml  # пароли ролей из Vault
kubectl apply -f clusters/casa/platform/cnpg/manifests/shared.cluster.yaml
kubectl get cluster -A -w                                # ждём healthy

kubectl apply -f clusters/casa/platform/cnpg/manifests/shared.databases.yaml
kubectl get cluster,database -A

# Выделенные кластеры поднимаются своими юнитами:
#   kubectl apply -k clusters/casa/apps/immich/manifests
#   kubectl apply -k clusters/casa/apps/zitadel/manifests
#   kubectl apply -k clusters/casa/apps/dawarich/manifests
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
  Поэтому базы вынесены в отдельные файлы, а в юните общего кластера — ещё и в
  волну 20: они применяются **после** того, как кластер волны 10 стал `healthy`.
  В юнитах сервисов волн нет (рядом живут рабочие нагрузки, и ожидание их
  готовности блокировало бы применение базы), поэтому залипшую `Database` видно
  по health-проверке CR: `Progressing`, пока `status.applied` не станет true.
- **`bootstrap` применяется только при создании.** Менять `initdb`-часть спеки
  у живого кластера бессмысленно — нужен пересоздатель.
- **Extension-image и `shared_preload_libraries` не менять одновременно.**
  Оператор предупреждает: сначала докати под с новым образом расширения, потом
  правь GUC. И любое добавление или обновление extension-image перезапускает
  поды всего кластера.
