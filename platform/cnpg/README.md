# CloudNativePG: кластеры баз

Оператор ставится через Argo CD (`argocd/applications/cloudnative-pg.yaml`), кластеры и
базы — обычные манифесты в этом каталоге, применяются руками. Argo ими не
управляет: его CRD должны существовать раньше релиза, а порядок «оператор →
CR» в одном Application не гарантирован.

Раскладка по namespace'ам и группировка баз — это решения с обоснованием в
`docs/adr/0001`, `0002` и `0003`; здесь — как это устроено и как этим
пользоваться. Термины («сервис», «общий кластер», «единица общей судьбы») — в
`CONTEXT.md`.

## Состав

| Кластер | Namespace | Базы (источник) | Роль | Размер на источнике |
|---|---|---|---|---|
| `shared` | `databases` | `nextcloud` | `nextcloud` | 42 МБ |
| `shared` | `databases` | `forgejo` | `forgejo` | 16 МБ |
| `shared` | `databases` | `synapse` (element) | `synapse` | 15 МБ |
| `shared` | `databases` | `paperless` | `paperless` | 17 МБ |
| `shared` | `databases` | `glitchtip` | `glitchtip` | 34 МБ |
| `shared` | `databases` | `infisical` | `infisical` | 160 МБ |
| `shared` | `databases` | `playground` | `playground` | 8 МБ |
| `shared` | `databases` | `gatus` (новая, не миграция) | `gatus` | — |
| `shared` | `databases` | `authentik` (тестовый стенд) | `authentik` | 115 МБ |
| `zitadel-db` | `zitadel` | `zitadel` | `zitadel` | 20 МБ |
| `immich-db` | `immich` | `immich` | `immich` | 287 МБ |
| `dawarich-db` | `dawarich` | `dawarich` | `dawarich` | 93 МБ |

Не входят: `sure` (PostgreSQL 16). `seafile` — это MariaDB, CNPG не про неё.

Четыре кластера вместо двенадцати отдельных Deployment'ов.

Имена: у выделенных кластеров суффикс `-db`, потому что они живут в namespace
сервиса, рядом с подами самого приложения — иначе `zitadel-1` и `zitadel-<hash>`
не различить. У общего кластера в `databases` суффикса нет: там и так только
базы. Имя `Cluster` определяет имена всего остального (под `<cluster>-1`,
сервисы `<cluster>-rw/-ro/-r`, PVC, секреты), а для приложения это ещё и
эндпоинт — поэтому в ADR 0003 версия в имени запрещена, а роль допускается.

## Почему так сгруппировано

Кластер — единица общей судьбы: он делит версию, расширения, окно
обслуживания, ресурсы инстанса, политику бэкапа и один PVC на инстанс. Поэтому
группируем по тому, что обязаны делить, и разносим там, где совместность
дорого стоит (полностью — в `docs/adr/0002`). Оси в порядке жёсткости:

1. **Версия и расширения** — не обойти: один `imageName` = один мажор и один
   набор расширений.
2. **Blast radius** — `zitadel-db` отдельно: падение IdP роняет всё, что логинится.
3. **Профиль нагрузки** — `immich-db` тяжелее всех остальных вместе.
4. **Политика бэкапа и окно обслуживания** — один кластер = один график.

Число инстансов — это уровень HA кластера, а не количество баз. Кластер
однонодный, поэтому везде `instances: 1`; при появлении второй ноды реплики
имеет смысл включать выборочно, начиная с `zitadel-db`.

## Почему в разных namespace'ах

Namespace — граница владения (`docs/adr/0001`). Выделенный кластер живёт рядом
со своим сервисом, общий — в нейтральном `databases`, потому что он
обслуживает несколько сервисов и не принадлежит ни одному из них.

Следствие, о которое легко споткнуться: **потребители `shared` ходят
cross-namespace** на `shared-rw.databases.svc.cluster.local`, а секрет роли
(`<app>-db-auth`) читается только из namespace кластера, то есть из
`databases`. Пароль нужен и в namespace сервиса — значит один источник правды и
синхронизация (Infisical, External Secrets или reflector), либо два
запечатанных SealedSecret'а из одного plaintext'а: `kubeseal` привязан к
namespace и имени.

Доступ приложение → база придётся разрешать явно: Calico NetworkPolicy
работает, но политик пока нет.

## Устройство кластера

Каждый кластер устроен одинаково:

- `bootstrap.initdb` создаёт **служебную** базу `app`/`app` со случайным
  паролем — просто чтобы initdb было что создать. Ни один сервис её не
  использует и особого статуса она не получает;
- реальные роли объявлены в `managed.roles`, реальные базы — объектами
  `Database` (`<cluster>.databases.yaml`).

## Объёмы

Размер тома задаёт не нагрузка, а служебный минимум. Замер на пустом PG18:
39 МБ — три шаблонные базы с системными каталогами (по ~7.4 МБ), `global/` и
один сегмент WAL в 16 МБ. Дальше прибавляются данные источника и умеренный
запас. Сверх vanilla-Postgres CNPG поднимает `wal_level` до `logical` и
`wal_keep_size` до 512MB; последний в кластерах опущен до 64MB (стендбаев нет),
иначе потолок всплеска WAL в полгигабайта заставлял бы раздувать каждый том.
Обратно том не сжимается, поэтому запас — не бесплатная опция: Longhorn
учитывает запрошенный размер при планировании.

Ориентиры: `shared` — пол + 292 МБ (с `infisical`) ≈ 331 МБ (том 1Gi),
`zitadel-db` — пол + 20 МБ
≈ 59 МБ (256Mi), `immich-db` — пол + 287 МБ и растёт с библиотекой (1Gi),
`dawarich-db` — пол + 93 МБ плюс запас под пересчёт истории (3Gi).

**Запас нужен под миграции, а не только под данные.** Обновление приложения с
data migrations (Dawarich 1.12 пересчитывал visits и tracks) временно раздувает
и таблицы, и WAL: том `dawarich-db` в 512Mi заполнился под завязку, и кластер
ушёл в `CrashLoopBackOff` с `no free disk space for WALs` (инцидент
`docs/incidents/0001`). Для сервисов с фоновым пересчётом закладывайте запас
сверх «данные + служебный пол».

### Как расширить том

Смена `spec.storage.size` **не прокатывается на PVC автоматически**: для
одноинстансного кластера оператор только сообщает
`PostgreSQL cannot proceed until the PVC group is enlarged`, а сам PVC не
трогает (реплики он пересоздаёт, primary — нет). Порядок из трёх шагов:

```sh
# 1. Увеличить размер в Cluster (и применить). Оператор увидит нехватку места.
kubectl apply -f platform/cnpg/<cluster>.cluster.yaml

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


## Расширения

Расширения различаются по области действия, и это определяет границы кластеров:

- **Уровень базы** (`CREATE EXTENSION`): `dawarich-db` — PostGIS. Соседи его не
  видят, поэтому «кому надо — использует, кому нет — всё равно» здесь честно.
  Отдельный кластер оправдан выгодой: обновление extension-образа перекатывает
  весь кластер, а мажорный апгрейд ждёт сборки расширения под новый PG.
- **Уровень кластера** (`shared_preload_libraries`): `immich-db` — VectorChord.
  Библиотека грузится в postmaster при старте, то есть во **всех** базах
  кластера. Поэтому vchord обязан жить в выделенном кластере.

Оба расширения приезжают через **Image Volume Extensions**: cloudnative-pg
монтирует OCI-образ расширения в контейнер read-only, а `CREATE EXTENSION`
выполняет оператор по объявлению в `Database`. Требования: PostgreSQL 18+,
k8s 1.35+ (на 1.33/1.34 — feature gate `ImageVolume`), containerd 2.1.0+ или
CRI-O 1.31+, чарт CNPG 0.26.0+. Расширение объявляется дважды и это не
дублирование: в `Cluster` — что смонтировать (бинари), в `Database` — что
выполнить в базе.

Про образы: у CNPG три типа. `minimal` — только PostgreSQL, без JIT с 18-й
версии. `standard` — плюс pgvector, все локали, PGAudit, JIT. `system` —
устаревший, `standard` + бинари Barman Cloud. `immich-db` берёт `standard`, потому
что vchord тянет за собой pgvector; остальным хватает `minimal`.

## Решения, которые пришлось принять (проверено на живых базах)

- **Коллация — ICU с нейтральной локалью `und`.** Имена локалей на источниках
  (`en_US.utf8`) оказались фантомными: образы на musl такой локали не имеют,
  PostgreSQL не мог определить версию коллации, а `COLLATE "en_US.utf8"` явно
  вообще не резолвился. Копировать эту «локаль» смысла не было, поэтому новые
  базы строятся на честных правилах: ICU не зависит от локалей в образе,
  одинакова везде и версионируется (`datcollversion` = версия ICU). `und` —
  общая таблица Unicode: и кириллица, и латиница сортируются корректно,
  латиница идёт первой. Отличие `ru-RU` только в порядке алфавитов (кириллица
  вперёд) — проверено на живых базах.
- **ctype ICU не заменяет.** `upper()`/`lower()` всегда идут через libc, поэтому
  явно задан `localeCType: C.utf8` — единственная UTF-8 локаль в
  `minimal-trixie`. С голым `C` регистр кириллицы не менялся бы (так сейчас в
  базе `element`). `builtin`-провайдер, в отличие от ICU, приносит и ctype, но
  сортирует по коду символа — для списков в UI это выглядит не по-людски.
- **Локаль окружения.** В образах CNPG `LANG` не задан: `setlocale` падает в
  `POSIX/C`, и интерактивный `psql` в поде разваливает многобайтовый ввод
  (`readline` считает терминал однобайтовым). Лечится `spec.env` с
  `LANG=C.utf8`; на клиентские запросы это не влияет (`psql -c` работает и без
  него, потому что не идёт через `readline`).
- **Имя роли `postgres` зарезервировано оператором.** Immich и sure сейчас
  ходят под `postgres`; для них заведена роль `immich` (sure — при переносе).
  Значит у сервиса меняются не только хост, но и пользователь.
- **Имена баз ≠ имена сервисов** у sure (`sure_production`). Dawarich при
  переносе переименован из `dawarich_production` в `dawarich`: суффикс шёл от
  `RAILS_ENV`, а среда в homelab одна.
- **Суперпользователь сервису не нужен.** `zitadel` и так работал
  непривилегированной ролью; Immich нужен был суперпользователь только ради
  `CREATE EXTENSION` — это закрывает `Database.spec.extensions`, где расширение
  создаёт оператор. Оператор 1.30 заодно заводит непривилегированную роль
  `cnpg_metrics_exporter` для встроенного экспортёра.
- **`immich` больше не на libc `en_US.utf8`.** Раньше его база была на
  PostgreSQL 14 (провайдер локали появился только в 15), и это запирало её на
  мажоре. Теперь база на 18 с ICU, а vectorchord ставится образом расширения —
  тот же рецепт, что в `immich-app/immich-charts`.
- **Пароли.** Роли ссылаются на `<app>-db-auth` (basic-auth, ключи
  `username`/`password`, label `cnpg.io/reload: "true"`) **в namespace
  кластера**. Так при миграции у сервиса меняется только хост. Secret'ы
  создаются на сервере, где лежит приватный ключ SOPS, и коммитятся
  зашифрованными.

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

## Первый запуск руками: test18

Начать стоит не с боевых кластеров, а с одноразового `test18`. Заодно это
проверка cross-namespace: кластер в `databases`, а секрет роли — там же, где и
кластер. Пароль лежит открытым текстом в `test18.secret.yaml` — он заведомо
тестовый, для боевых баз так нельзя.

```sh
# 0. Namespace'ы: databases, zitadel, immich, dawarich
kubectl apply -f platform/cnpg/namespaces.yaml

# 1. Оператор: в Argo приложение и sync, либо
kubectl apply -f argocd/applications/cloudnative-pg.yaml
argocd app sync cloudnative-pg
kubectl -n cnpg-system get pods -w

# 2. Secret раньше кластера: из него берётся пароль роли test18
kubectl apply -f platform/cnpg/test18.secret.yaml
kubectl apply -f platform/cnpg/test18.cluster.yaml
kubectl -n databases get cluster test18 -w   # ждём Cluster in healthy state

# 3. База — только когда кластер healthy (см. «Грабли»)
kubectl apply -f platform/cnpg/test18.databases.yaml
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
kubectl delete -f platform/cnpg/test18.databases.yaml   # базу удаляем отдельно
kubectl delete -f platform/cnpg/test18.cluster.yaml
kubectl delete -f platform/cnpg/test18.secret.yaml
```

## Предусловия

1. Оператор установлен и CRD есть: `kubectl -n cnpg-system get deploy`.
2. Namespace'ы созданы: `kubectl apply -f platform/cnpg/namespaces.yaml`.
3. Созданы basic-auth Secret'ы ролей — запечатаны в `db-auth.sealedsecrets.yaml`
   и применяются в **namespace своего кластера**:
   - `databases`: `nextcloud-db-auth`, `forgejo-db-auth`, `element-db-auth`
     (роль `synapse`), `paperless-db-auth`, `glitchtip-db-auth`,
     `infisical-db-auth`, `postgres-db-auth` (роль `playground`), `gatus-db-auth`,
     `authentik-db-auth`;
   - `zitadel`: `zitadel-db-auth`;
   - `immich`: `immich-db-auth`;
   - `dawarich`: `dawarich-db-auth`.

   Пароли переиспользованы из Secret'ов сервисов, чтобы при миграции менялся
   только хост. Перезапечатать можно только на сервере: `kubeseal` привязан к
   namespace и имени, а приватный ключ контроллера доступен лишь там
   (`docs/agents/server-access.md`).

Без Secret'ов кластер поднимется, а роли и базы останутся неотреконсиленными —
это видно в `kubectl -n <ns> get cluster <name> -o yaml` и в статусе
`Database`-объектов.

## Установка

Порядок важен: namespace'ы → кластеры → дождаться `healthy` → базы. Иначе
`Database`-объекты один раз увидят отсутствующий кластер и залипнут в
`applied: false` (см. «Грабли»).

```sh
kubectl apply -f platform/cnpg/namespaces.yaml
kubectl apply -f platform/cnpg/db-auth.sealedsecrets.yaml     # пароли ролей
kubectl apply -f argocd/applications/cloudnative-pg.yaml          # оператор (+ sync в Argo)
kubectl -n cnpg-system get pods -w

kubectl apply -f platform/cnpg/*.cluster.yaml
kubectl get cluster -A -w                                # ждём healthy

kubectl apply -f platform/cnpg/*.databases.yaml
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

## Что ещё не сделано

- **Метрики.** У оператора нет CRD prometheus-operator, поэтому PodMonitor не
  используется. Вместо него — job `cnpg` в
  `apps/victoria-metrics/k8s/vmagent.configmap.yaml`: service discovery по подам,
  keep по порту `metrics`, лейблы `cluster`/`role` из `cnpg.io/cluster` и
  `cnpg.io/podRole`, служебные базы (`template*`, `postgres`, `app`) отброшены
  по `datname`. Для баз на CNPG отдельные экспортёры
  (  `apps/db-exporters/k8s/postgres.exporters.yaml`) больше не нужны: они сняты
  для `immich`, `dawarich`, `zitadel`, `paperless`, `infisical`, `glitchtip` и
  `playground`. Остальные (`authentik`, `element`, `forgejo`, `nextcloud`,
  `sure`) — до их переезда.
- **Бэкапы.** Ради них всё и затевается: ObjectStore/ScheduledBackup в rustfs
  (S3-совместимый) + **Barman Cloud Plugin** дают непрерывные бэкапы и PITR
  вместо текущего «dump перед restic». В `standard`-образах бинарей Barman нет
  (они только в устаревшем `system`), поэтому путь — именно плагин. Настроить
  до переноса реальных данных.
- **Namespace'ы сервисов.** Пока переехали только кластеры баз; сами сервисы
  остаются в `default` и ходят cross-namespace. Переезд инкрементальный:
  SealedSecret перешифровать, Ingress и TLS-секрет положить в свой namespace,
  PVC пересоздать.
- **NetworkPolicy.** Default-deny в каждом namespace плюс явные разрешения
  «сервис → его база» в обе стороны. Сейчас политик нет вообще.
- **Helm-чарты.** Сервисы переезжают на чарты (Immich — официальный
  `oci://ghcr.io/immich-app/immich-charts/immich`, Forgejo — `forgejo-helm`).
  У чартов **выключается встроенная база** и указывается внешний хост, иначе
  консолидация отменяется и чарты поднимают по случайному Postgres'у.
- **Second node.** При появлении второй ноды: `instances: 3` для `zitadel-db`
  (и, возможно, `shared`), anti-affinity уже дефолтная.
