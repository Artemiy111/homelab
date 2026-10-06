# Grafana

Grafana — единый UI для дашбордов поверх VictoriaMetrics. Сервис развёрнут в
Kubernetes (`apps/grafana/`) и доступен через Traefik кластера по адресу
`https://grafana.example.com/` за `oauth2-proxy`.

Отделён от `apps/victoria-metrics/`: Grafana — независимый слой визуализации
(свои образ, данные, секрет и маршрут), который лишь читает метрики из
VictoriaMetrics как datasource.

## Данные и доступ

- Инстанс описан CR `Grafana` в `k8s/grafana.yaml`; им управляет
  `grafana-operator` (`argocd/applications/grafana-operator.yaml`).
- Образ `grafana/grafana:13.2.0` (зафиксирован по digest) — в `spec.version`
  единственного CR, это единственное место, где закреплена версия.
- Данные (пользователи, дашборды, алерты, аннотации) — PostgreSQL в общем
  кластере CNPG `shared` (namespace `databases`, эндпоинт
  `shared-rw.databases.svc.cluster.local:5432`). Роль `grafana`, база `grafana`
  и NetworkPolicy объявлены в `platform/cnpg/`; пароль приходит в под из
  Secret'а `grafana-db` (ключ `GRAFANA_DB_PASSWORD`).
- Локальный диск под `/var/lib/grafana` — `emptyDir`: это только скретч (кэш
  плагинов, индекс поиска), сами данные в Postgres, поэтому том не нужен.
  Тома монтирует оператор, uid/gid и `readOnlyRootFilesystem` — его дефолты.
- Логин администратора — `admin`, пароль — в кластерном Secret `grafana-admin`
  (`GRAFANA_ADMIN_PASSWORD`), синхронизируется из Vault по
  `k8s/vaultstaticsecret.yaml`. Регистрация новых пользователей
  отключена; доступ к UI контролирует `oauth2-proxy`, локальный вход нужен для
  правок datasource и диагностики. Свой admin-секрет оператора отключён
  (`disableDefaultAdminSecret: true`), пароль в нём не дублируется.
- Пароли `GRAFANA_ADMIN_PASSWORD` и `GRAFANA_DB_PASSWORD` лежат в Vault
  (`kv/grafana/admin` и `kv/grafana/@grafana/db`, второй — выданный CNPG).
- `NTFY_TOPIC` для метрических алертов — в отдельном Secret'е `grafana-ntfy`
  (путь `kv/ntfy/topic`). Отдельный путь, потому что темой делится ещё и gatus:
  один путь `kv/ntfy/topic` читают два `VaultStaticSecret` — `grafana-ntfy` и
  `gatus-ntfy`, значение хранится один раз.

### Плагины

Все четыре datasource-плагина (`prometheus`, `loki`, `tempo`,
`grafana-pyroscope-datasource`) встроены в образ Grafana. Плюс на старте
скачиваются пять observability-приложений — `grafana-lokiexplore-app`,
`grafana-pyroscope-app`, `grafana-metricsdrilldown-app`,
`grafana-exploretraces-app`, `grafana-advisor-app`. Именно последние дают меню
Drilldown (Logs / Metrics / Traces / Profiles) в дашбордах.

**Корень файловой системы должен быть writable** (`readOnlyRootFilesystem` не
задан), иначе Grafana не запускается рабочим. При старте фоновый установщик
сверяет встроенные плагины с каталогом grafana.com и обновляет их на месте в
`/usr/share/grafana/data/plugins-bundled`. На read-only ФС происходит:

1. `Unload` плагина из реестра — выполняется;
2. удаление файлов — падает с `read-only file system`;
3. плагин остаётся на диске, но больше не в реестре.

Дальше datasource'и не отвечают (`plugin.notRegistered` в
`/api/datasources/uid/<uid>/health`), панели пустые, а **ни одно правило
алертинга не вычисляется** — в `alert_rule_state` нет ни одной строки. При этом
Grafana выглядит живой: под `Running`, `GrafanaReady=True`, правила в UI есть.

Поэтому в CR стоит `disableDefaultSecurityContext: "Container"` — оператор
перестаёт навешивать свой `readOnlyRootFilesystem`, а `securityContext`
контейнера описан явно (non-root, drop ALL, seccomp). Отключать preinstall
(`GF_PLUGINS_PREINSTALL_DISABLED`) нельзя: вместе с автообновлением это
гасит и установку observability-приложений, а они не встроены в образ и
качаются с grafana.com — Drilldown пропадает навсегда.

Проверять после смены версии образа и после любой смены образа вообще:

```sh
kubectl -n monitoring exec deploy/grafana-deployment -c grafana -- sh -c \
  'curl -s -u "admin:$GF_SECURITY_ADMIN_PASSWORD" \
     "http://127.0.0.1:3000/api/datasources/uid/victoriametrics/health"'
```

Ожидается `{"status":"OK",...}`. Ответ `plugin.notRegistered` означает, что
плагины выпали из реестра, и алертинг молча слепой.

Drilldown проверяется отдельно — наличием приложений в реестре:

```sh
kubectl -n monitoring exec deploy/grafana-deployment -c grafana -- sh -c \
  'curl -s -u "admin:$GF_SECURITY_ADMIN_PASSWORD" \
     "http://127.0.0.1:3000/api/plugins?embedded=0"' | jq -r '.[].id' | grep app
```

Ожидаются все пять `*-app`. Пусто — меню Drilldown будет пустым, и алертинг
при этом выглядит исправным.

## Datasource'ы

Четыре источника описаны CR `GrafanaDatasource` в `k8s/datasources.yaml`, ими
управляет оператор: `victoriametrics` (`http://victoriametrics:8428`, default),
`tempo` (`http://tempo:3200`), `loki` (`http://loki:3100`),
`pyroscope` (`http://pyroscope:4040`). Секретов нет — все четыре анонимные.

uid зафиксированы в `spec.datasource.uid`: на них ссылаются панели дашбордов из
`config/dashboards/`, и смена uid удалила бы старый datasource и создала новый —
дашборды остались бы без источника.

Связи между источниками: из трейса можно уйти в логи (`tracesToLogsV2` у Tempo),
из лога — в трейс (`derivedFields` по `trace_id` у Loki), из профиля — в трейс
(`tracesToProfiles` у Pyroscope). У Traefik включены JSON access-логи
(`accessLog` в `argocd/applications/traefik.yaml`), и в них есть поле
`trace_id`, поэтому переходы trace↔log находят результат: логи Traefik попадают
в Loki через Alloy.

Значения `${...}` уходят в Grafana как есть — подстановки переменных
провижининга на этом пути больше нет. Это чинит ошибку, которая была не видна
в конфиге: у `tracesToProfiles.serviceName` в файле провижининга стояло
`'${__field.labels.service_name}'` без экранирования, Grafana применил свою
подстановку и записал в БД пустую строку, то есть связь профиль→трейс не
работала. Значения Tempo и Loki экранировались как `$$`, это — нет.

**Datasource'ы редактируемы в UI, и это необратимо.** Раньше их делал
провижининг с `editable: false`, и Grafana отдавал их как read-only: правка через
API отвечала 403. У `UpdateDataSourceCommand` поля `editable` нет, а `ReadOnly`
помечен `json:"-"` — read-only не выставляется через API в принципе. Практически:
правка в UI переживёт до ресинка оператора (`defaultResyncPeriod`, 10m) и будет
перезаписана. Для дашбордов защита не потеряна, см. раздел «Дашборды»: там
реконсилей не пропускает хэш, и ручная правка откатывается за 10 минут.

Проверка после правки CR:

```sh
kubectl -n monitoring get grafanadatasource
kubectl -n monitoring exec deploy/grafana-deployment -c grafana -- sh -c \
  'curl -s -u "admin:$GF_SECURITY_ADMIN_PASSWORD" \
     "http://127.0.0.1:3000/api/datasources/uid/victoriametrics/health"'
```

## Дашборды

Шесть дашбордов описаны CR `GrafanaDashboard` в `k8s/dashboards.yaml`, все в
папке `homelab` (`GrafanaFolder`, та же CR — на неё ссылаются и правила
алертинга). JSON лежит в `config/dashboards/`, собирается в ConfigMap
`grafana-dashboards` и подтягивается оператором через `spec.configMapRef` — JSON
не дублируется в CR: 249 КБ на `cloudnative-pg` в CR были бы нечитаемым
объектом на четверть мегабайта.

Дашборды: `cloudnative-pg.json` и `postgresql-database.json` — экспорт из UI
Grafana; `traefik.json` — написан руками под метрики Traefik;
`traefik-official.json` — официальный дашборд Traefik с grafana.com, вендорен с
правками под наш datasource (см. ниже); `storage-capacity.json` — обзор
заполняемости томов: PVC по `kubelet_volume_stats_*`, тома и узлы Longhorn по
`longhorn_*`, файловые системы узла.

`traefik.json` и `traefik-official.json` не дублируют друг друга: официальный
не содержит ни одного запроса `traefik_router_*` (все 14 панелей смотрят на
service/entrypoint), per-router панели есть только в самописном. Per-router
метрики появляются с `metrics.prometheus.addRoutersLabels=true` в
`argocd/applications/traefik.yaml` (#284).

**Правки в UI откатываются сами.** У реконсиля `GrafanaDashboard` нет пропуска
реконсиля по хэшу, он перезаписывает дашборд на каждом проходе, а период
ресинка 10m. То есть ручная правка живёт не дольше десяти минут — это даже
строже, чем было при провижининге с `allowUiUpdates: false`, где откат
происходил только при рестарте Grafana. (У datasource'ов наоборот: там пропуск
по хэшу есть, см. раздел выше.)

Проверка после правки JSON:

```sh
kubectl -n monitoring get grafanadashboard
kubectl -n monitoring logs deploy/grafana-operator --since=30s | grep -c DashboardReconciler
```

Второй счётчик обязан быть больше нуля: без лейбла
`app.kubernetes.io/managed-by` на ConfigMap'е watch не срабатывает и правка
молча не применяется.

Провижининг алертинга остался только ради contact point — `config/alerting/`,
монтируется в `/etc/grafana/provisioning/alerting` тем же
`configMapGenerator`. Правила и дерево политик ими управляет оператор
(`k8s/alerts.yaml`), и в провижининге им не место. Grafana перечитывает
провижининг **только на старте**, поэтому рестарт при правке конфига
обязателен. Его делает оператор: в pod template есть аннотация
`checksum/secrets` — SHA от содержимого всех Secret и
ConfigMap, упомянутых в CR. Отсюда следует, что суффикс-хэш у ConfigMap'ов
отключён (`generatorOptions.disableNameSuffixHash`) — иначе имя менялось бы при
каждой правке и ссылаться на него из CR было бы нельзя.

### Лейбл managed-by на ConfigMap'ах — не украшение

Информер оператора фильтрует ConfigMap'ы и Secret'ы по лейблу
`app.kubernetes.io/managed-by: grafana-operator` (`main.go`,
`mgrOptions.Cache.ByObject`). На ConfigMap'ы без этого лейбла watch не
срабатывает: чтение идёт напрямую через `DisableFor`, поэтому `checksum/secrets`
считается верно, но правка ConfigMap **не вызывает реконсиль и не перезапускает
под** — изменение молча не применяется, и это выглядит как «опять сломалось».

Поэтому лейбл задан в `options.labels` каждого `configMapGenerator` в
`kustomization.yaml`, и снимать его нельзя. Проверяется так:

```sh
kubectl -n monitoring get cm grafana-alerting \
  -o jsonpath='{.metadata.labels}' | grep managed-by
kubectl -n grafana-operator logs deploy/grafana-operator --since=30s | grep -c GrafanaReconciler
```

После `kubectl apply -k apps/grafana/` второй счётчик обязан быть больше нуля.

Побочный эффект того же механизма: **ротация секретов применяется сама**.
`grafana-admin`, `grafana-db` и `grafana-ntfy` обновляются VSO на месте, `env`
перечитывается только при рестарте, а `checksum/secrets` меняется вместе с
содержимым Secret'а — под перезапускается без `rollout restart`. До переезда на
оператора это было главным дефектом схемы (ротация пароля БД не применялась до
рестарта).

JSON-файлы хранятся в читаемом виде (`indent=2`), суммарно 337946 Б. Это больше
лимита аннотации `kubectl.kubernetes.io/last-applied-configuration` (262144 Б),
с которым падает client-side apply, поэтому **Grafana применяется только
server-side apply** — он эту аннотацию не пишет:

```sh
kubectl apply --server-side --field-manager=homelab -k apps/grafana/
```

Остальные приложения репозитория пока применяются client-side; переход на
server-side для них — отдельная задача, не смешивать её с правками Grafana.
Причина миграции именно в размере: client-side apply падает на лимите аннотации
(проверено на стенде — `metadata.annotations: Too long` при 337946 Б). Побочный
плюс server-side — владение полями в `metadata.managedFields`, но на повреждённый
ConfigMap это не влияет, и отдельного подтверждения не требует.

Дашборды: `cloudnative-pg.json` и `postgresql-database.json` — экспорт из UI
Grafana; `traefik.json` — написан руками под метрики Traefik;
`traefik-official.json` — официальный дашборд Traefik с grafana.com, вендорен с
правками под наш datasource (см. ниже); `storage-capacity.json` — написан
руками обзор заполняемости томов: PVC по `kubelet_volume_stats_*`, тома и узлы
Longhorn по `longhorn_*`, файловые системы узла.

`traefik.json` и `traefik-official.json` не дублируют друг друга: официальный
не содержит ни одного запроса `traefik_router_*` (все 14 панелей смотрят на
service/entrypoint), per-router панели есть только в самописном. Per-router
метрики появляются при `metrics.prometheus.addRoutersLabels=true` в
`argocd/applications/traefik.yaml` (#284).

### Вендоренные дашборды с grafana.com

Grafana не умеет импортировать дашборд с grafana.com по ID в рантайме —
провижининг читает только файлы, git или HTTP. Поэтому community-дашборд
скачивается один раз и коммитится, а обновляется вручную.

| Файл | grafana.com ID | Ревизия | revisionId | uid в Grafana |
|---|---|---|---|---|
| `traefik-official.json` | 17346 | 9 | 33826 | `traefik-official` |

Файл **не** хранится дословной копией оригинала — в нём три отличия, каждое
вызвано конкретной ошибкой, а не stylistic выбором:

1. **`datasource` у всех панелей, targets и query-переменных заменён на
   `uid: victoriametrics`.** В оригинале везде `${DS_PROMETHEUS}`. Если datasource
   переменной не резолвится, Grafana показывает «Datasource ${DS_PROMETHEUS} was
   not found», а панели, фильтруемые по `$service`/`$entrypoint`, остаются пустыми.
   Так же сделано в `cloudnative-pg.json` и `postgresql-database.json`.
2. **Переменная `DS_PROMETHEUS` оставлена объявленной**, но на неё никто не
   ссылается — как в двух других дашбордах. Удалять её нельзя: Grafana 13
   отбрасывает `type: datasource` переменные при загрузке из файла, и если
   объявить, но не использовать, её исчезновение ничего не ломает.
3. **`uid` — `traefik-official`, а не оригинальный `n5bu_kv45`.** С оригинальным
   uid провижининг падал при каждой попытке сохранения:
   `Operation cannot be fulfilled on dashboards.dashboard.grafana.app "n5bu_kv45":
   deprecatedInternalID=... is already in use`. Пока uid не совпадает с тем, что
   уже занято в unified storage, дашборд не перезаписывается — молча, без
   ошибки в интерфейсе. Проверять это надо по логам Grafana
   (`logger=provisioning.dashboard`), а не по содержимому БД: несохранённый
   файл выглядит в базе как валидный.

Обновление: перекачать JSON, повторить те же три правки, обновить ревизию в
таблице выше.

```sh
curl -s -o apps/grafana/config/dashboards/traefik-official.json \
  https://grafana.com/api/dashboards/17346/revisions/latest/download
```

После применения **проверять логи**, а не только состояние Grafana:

```sh
kubectl logs deploy/grafana-deployment -n monitoring --tail=200 | grep provisioning.dashboard
```

Ожидается `finished to provision dashboards` без записей `level=error`.

## Алёрты

Движок — **Grafana Unified Alerting** с правилами в `k8s/alerts.yaml`
(`GrafanaAlertRuleGroup`). Это осознанный промежуточный выбор:
vmalert + Alertmanager дали бы независимость evaluation от процесса Grafana,
`keep_firing_for` и переносимые PromQL-правила, но стоили бы двух новых
Deployment, PVC под `nflog`/silences и правки `platform/monitoring/
networkpolicy.yaml`. Пока в кластере один узел и меняются в основном правила,
это не окупается. Возврат к vmalert — отдельная задача, когда появится
требование, которое Grafana не закрывает.

Правила **в коллекции не редактируются**: ими управляет оператор, и правка в UI
откатывается при реконсиле. Дерево политик — `GrafanaNotificationPolicy`, оно
тоже перезаписывает дерево целиком вместе с политиками, созданными в UI.

Четыре папки алертов объявлены как `GrafanaFolder` в том же файле: без них
`GrafanaAlertRuleGroup` невалиден — требует ровно одну из `folderUID`/`folderRef`.
Оператор находит существующую папку по `spec.title`, а не по имени CR, поэтому
CR с кириллическим `title` (`Хранилище`, `Сертификаты`) подхватывают уже
созданные папки и не плодят дубликаты.

**У всех четырёх папок закреплён `spec.uid`, и это не косметика.** Оператор ищет
папку по uid, а при промахе откатывается на поиск по title — и тогда
`GetGrafanaUID()` возвращает `metadata.uid` объекта Kubernetes, а не uid папки в
Grafana. Для папки, созданной оператором, это неотличимо: новой папке оператор
сам назначает uid из `metadata.uid`. Для папки, доставшейся от провижининга, uid
короткий (`dfzmtnvaln6yoe`), и `folderRef` в группе правил уходит с
`folder with uid <metadata.uid> not found`. Над этим есть TODO в коде оператора:
`GetGrafanaUID() can be wrong when the fallback to search is used`.

Побочная польза закреплённого uid: набор папок воспроизводится из git. Без него
пересозданная БД Grafana дала бы папкам новые uid, а группы правил, ссылающиеся
на старые, остались бы битыми.

`spec.uid` неизменяем (CEL-валидация на CRD), поэтому папки, созданные без него,
пришлось пересоздать. Пересоздание в кластере делалось снятием finalizer'а
`operator.grafana.com/finalizer` перед удалением CR: иначе finalizer удаляет папку
в Grafana вместе с её правилами (`DeleteFolder` с `forceDeleteRules=true`), а
задача была в том, чтобы папки и правила не пропали.

### Канал доставки

Один канал — **ntfy** (`https://ntfy.sh/$NTFY_TOPIC?template=alertmanager`),
через `webhook`-contact point: встроенной интеграции ntfy в Grafana нет.
Параметр `template=alertmanager` заставляет ntfy отформатировать тело, иначе
уведомление приходит JSON-конвертом целиком. Тема приходит из Secret'а
`grafana-ntfy` (`NTFY_TOPIC`) и совпадает с темой Gatus, поэтому проверки
доступности и метрические алерты приходят в один поток.

Шаблон `alertmanager`, а не `grafana`: первый рассчитан на payload Unified
Alerting (`receiver`/`status`/`alerts[]`), второй — на плоский legacy-формат
`{status, title, message}` и на нашем payload падает с 400.

**Тема лежит в URL открыто — это осознанно принятый риск.** Публичный
`ntfy.sh` не включает access control («all topics on ntfy.sh are public»), и
защитить топик токеном там нельзя: тема и есть пароль. Спрятать её из URL тоже
нельзя — ntfy принимает топик либо в пути, либо в JSON-теле, а Grafana webhook
не умеет подставлять своё тело. Значит на публичном инстансе тема обязана быть
в URL, а значит — в contact point'е, в БД Grafana и в экспорте конфигурации.

Решение владельца — оставить как есть: Grafana закрыта oauth2-proxy, в UI
contact point'а попасть может только владелец, а секрет низкой ценности (утечка
даёт чтение алертов и спам в телефон, но не доступ к чему-то ценному).
Оставшаяся поверхность шире интерфейса: тема лежит открытым текстом в
Postgres Grafana (`alert_configuration.alertmanager_configuration`), то есть
утечёт через дампы БД, доступ к роли `grafana` в `shared-rw.databases` или
экспорт конфигурации через API.

Что проверено и работает: `authorization_credentials` у webhook складывается
Grafana в `secureSettings` и в БД лежит зашифрованным (проверено на стенде —
значение не находится открытым текстом ни в одной колонке). Поэтому схема
«токен в `secureSettings`, тема — просто имя» реализуема, но **только на
self-hosted ntfy** с `auth-default-access: deny-all`; там Android push требует
собственного Firebase-ключа или UnifiedPush, то есть надёжность доставки в
фоне падает. Если тема в БД Grafana когда-нибудь станет неприемлема, вариант
без потери push — вынести ntfy-конфиг во внутренний Alertmanager
(`prometheus-alertmanager`-contact point): тогда тема живёт в Vault, а не
в БД Grafana. Отдельная задача.

Два артефакта рендера, которые не лечатся с нашей стороны (шаблон — файл ntfy):
`Instance: <no value>`, потому что наши правила не несут лейбла `instance`, и
`Ends at: 0001-01-01T00:00:00Z` для firing-алертов — шаблон проверяет `endsAt`
на truthy, а Grafana шлёт нулевое время.

Telegram сознательно не подключён: из кластера **не доходит**
`api.telegram.org` (проверено с пода в `monitoring` — соединение не
устанавливается). Gatus ходит в Telegram через прокси 3x-ui на порту 8440
(`apps/gatus/k8s/deployment.yaml`), который Grafana не разделяет. Чтобы
добавить Telegram, нужно сначала доказать, что alerting-нотификаторы Grafana
уважают `[proxy] https_proxy` — иначе contact point будет уходить в никуда
молча. Перед добавлением любого contact point с `secure_settings` (например
`bottoken` у telegram) нужно задать `GF_SECURITY_SECRET_KEY`: Grafana
зашифровывает такие значения ключом `security.secret_key`, и если в БД уже
есть зашифрованные значения, смена ключа ломает их безвозвратно. Сейчас
зашифрованных значений в БД нет, поэтому ключ можно задать в любой момент
без потерь.

### Почему contact point остался в провижининге

Единственный объект алертинга, который не переехал в git — сам contact point
(`config/alerting/contact-points.yaml`). Формально для него есть
`GrafanaContactPoint` с `valuesFrom.secretKeyRef`, и это выглядит как решение
одной строкой. Оно не годится по двум причинам, обе проверены в коде
`controllers/contactpoint_controller.go` v5.25.0.

Первая: `valuesFrom` не подставляет значение в шаблон, а **заменяет поле
целиком** — `simpleContent.SetPath(...)`. Значит в секрете должен лежать весь
URL `https://ntfy.sh/<тема>?template=alertmanager`, а не только тема. В Vault
есть только `ntfy/topic`, а Vault KV v2 не умеет композицию, так что путь
`ntfy/url` пришлось бы заводить руками.

Вторая: та же строка логирует подставленное значение —
`log.V(1).Info("overriding value", ..., "value", val)`. Сейчас это не видно:
оператор запущен с `--zap-log-level=info`, а `V(1)` уходит в debug-ветку и
отфильтровывается. Но Alloy отправляет в Loki stdout **всех** подов без
фильтра по namespace, поэтому любой `--zap-log-level=debug` (например, при
разборе зависшего реконсиля) навсегда утечёт тему в индекс логов. Пока тема
лежит в БД Grafana и в env пода, её достать можно только через БД или API, а
не через grep по логам.

Вернуться к CR можно, если выполнить оба условия: завести в Vault путь с
полным URL (`ntfy/url`) и не опускать лог оператора ниже `info`.

### Правила и пороги

Пороги подобраны под PVC `victoriametrics-vmdata` = 8Gi и темп роста данных
≈200 МБ/сутки (замерено 2026-09-26: `deriv(vm_data_size_bytes{type=
"storage/big"}[7d])`). На момент настройки свободно 4.16 ГБ, `min_over_time
(vm_free_disk_space_bytes[7d])` = 98 МБ — то есть за неделю до этого диск
реально доходил до 94 МиБ свободных.

| uid | severity | Условие | `for` | Смысл |
|---|---|---|---|---|
| `vm-storage-read-only` | critical | `vm_storage_is_read_only == 1` | 1m | TSDB не принимает запись |
| `vm-pending-rows-backlog` | warning | `max(vm_pending_rows) > 1e6` | 30m | очередь не сбрасывается на диск |
| `scrape-target-down` | warning | `count by (job) (up == 0) > 0` | 10m | таргет отвечает, но метрики не читаются |

Место на диске **не** проверяется отдельными правилами под VictoriaMetrics:
это делает группа `storage` для всех PVC кластера разом — `pvc-low-free-space`
(абсолютный порог) и `pvc-will-fill-in-3-days` (`predict_linear`). До них в
`config/alerting/` жили точечные правила под каждый том
(`vm-free-disk-space-low`, `loki-disk-low` и ещё три), и они были удалены из
git без `deleteRules`, то есть **остались вычисляться в Grafana**. Переход на
`GrafanaAlertRuleGroup` их удалил: группа обновляется целиком, и правила, которых
нет в `spec.rules`, выносятся из Grafana.

Каждое правило — цепочка из трёх узлов, и это не косметика (обе части
обязательны, проверено на стенде):

- **A** — запрос к VictoriaMetrics. В его `model` обязан лежать **вложенный**
  `datasource: {type, uid}`. Одного `datasourceUid` на уровне запроса
  недостаточно: планировщик ищет datasource по полям `model`, не находит и падает
  при каждой оценке с `plugin.notRegistered`, а правило при этом молча не
  считается — в UI оно выглядит как созданное;
- **B** — выражение `reduce` с `reducer: last`;
- **C** — выражение `threshold` с `evaluator: gt 0`, и вот оно уже стоит в
  `condition`.

Порог 0 отделяет сработавшее от не сработавшего: сами выражения уже
фильтруют (`< 1.5e9` возвращает пустой вектор, когда условие не выполнено), а
`reduce`/`threshold` превращают «вернулась серия» в решение `Alerting`. Пустой
вектор — это «условие не выполнено», поэтому у всех правил
`noDataState: OK`.

Намеренно мало правил, а не полный набор: каждое лишнее правило растит шанс,
что его начнут игнорировать, а алерт-фатиг обесценивает систему целиком.
Порядок расширения: сначала то, что молча ломает метрики, потом остальное.

### Известные дыры

- **`pvc-will-fill-in-3-days` слепнет на 1 сутки после рестарта или расширения
  PVC.** Свободное место прыгает вверх, наклон линейной регрессии становится
  нулевым, прогноз уходит в плюс. В это окно работает только абсолютный порог
  `pvc-low-free-space` — поэтому оба правила нужны.
- **`scrape-target-down` не ловит недоступный таргет.** Если vmagent упал, его
  метрики станут stale и исчезнут из TSDB, а `up == 0` не сработает — читать
  алерт будет некому. Этот случай закрывают HTTP-проверки Gatus
  (`victoriametrics`, `vmagent`, `grafana` в `apps/gatus/config/config.yaml`):
  Gatus не зависит от VictoriaMetrics и переживает её падение.
- **Grafana — точка отказа самого алертинга.** Пока evaluation живёт в процессе
  Grafana, её рестарт = пауза в оценке правил. При `replicas: 1` и дефолтном
  RollingUpdate старый под доходит до `Ready` раньше, чем новый вытесняется, так
  что разрыва в оценке на практике нет.

### Проверка

Оператор доставил правила — по статусам CR, а не по логам Grafana:

```sh
kubectl -n monitoring get grafanacontactpoints,\
grafananotificationpolicies,\
grafanaalertrulegroups -o json |
  jq -r '.items[] | "\(.kind)/\(.metadata.name)\t\(.status.conditions[0].status)\t\(.status.conditions[0].message // "")"'
```

Все условия должны быть `True` / `ApplySuccessful`. `grafanacontactpoints` в
списке пуст — contact point остался в провижининге, и это ожидаемо.

Правила загружены — по логам провижининга:

```sh
kubectl logs deploy/grafana-deployment -n monitoring --tail=200 | grep -i provisioning.alerting
```

Ожидается `finished to provision alerting` без записей `level=error`. Две
записи `file has invalid suffix '..data'` — это норма: ConfigMap-проекция
кладёт рядом служебные каталоги, Grafana их пропускает.

При первом вычислении после старта пода отдельное правило может один раз
упасть с `plugin.notRegistered` (`attempt=1`): планировщик успевает
добраться до правила раньше, чем реестр плагинов datasource'а. Повтор
проходит успешно, в устойчивом режиме ошибок нет. Если ошибка повторяется на
каждом цикле — это уже не гонка старта, а отсутствие вложенного `datasource`
в `model` (см. «Правила и пороги»).

**Правило удаляется из git без танцев с `deleteRules`.** Такая необходимость
была только при провижининге: он создаёт и обновляет, поэтому убрать файл из
`config/alerting/` значило оставить правило в БД навсегда — оно продолжит
считаться и слать уведомления, и именно так в кластере накопилось пять таких
правил. С `GrafanaAlertRuleGroup` удаление выводится из трёх строк кода
(`controllers/alertrulegroup_controller.go`): группа обновляется целиком через
`PUT /api/v1/provisioning/alert-rules/{group}`, и правила, которых нет в теле,
Grafana удаляет; удаление самого CR убирает группу целиком.

**Grafana не отдаёт правила, созданные из файлов, под управление API.** Это
ограничение, а не сбой, и оно делает перенос правил на CR разовым действием, а
не повторяемой процедурой.

`CanUpdateManagerInRuleGroup` (Grafana, `pkg/services/ngalert/provisioning/validation/provenance.go`):

- тот же вид менеджера — можно;
- сохранённый вид `unknown` — можно;
- сбрасывать в `unknown` разрешено только API-источникам;
- **всё остальное — 409**.

Объяснение в коде: у file- и repo-источников состояние живёт снаружи Grafana
(файл провижининга, git-репозиторий), и запись изнутри Grafana молча свела бы
её с этим источником в рассинхрон. Правила из файлов хранятся как
`classicFP`, приходят от оператора как `kubectl` — виды разные, значит 409 на
`PUT /api/v1/provisioning/folder/{folderUid}/rule-groups/{group}`.

Практическое следствие: правила, созданные провижинингом, сначала надо удалить
из Grafana, и только потом создавать через оператора. Проверено на стенде —
все группы пересоздались за один реконсиль после удаления папок с
`forceDeleteRules=true`. Поскольку удаление папки сносит её правила, а
`GrafanaAlertRuleGroup` их тут же вернёт из git, разрыв алертинга — секунды.
Положительная сторона: правила, удалённые из git раньше без `deleteRules`,
уходят вместе с ними.

Побочный эффект, о котором стоит помнить: применение `GrafanaAlertRuleGroup`
объявляет git источником истины для всей группы. Правило, созданное руками в
UI, исчезнет при следующем реконсиле — это цена за отсутствие зомби.

**Правила вычисляются** — по таблице состояний в БД Grafana, а не по UI.
Это единственная проверка, которая ловит правило, которое применилось, но
не считается: в интерфейсе оно при этом выглядит как рабочее.

```sh
kubectl exec -i shared-1 -n databases -c postgres -- \
  psql -U postgres -d grafana -c \
  "SELECT count(*) AS evaluated,
          count(*) FILTER (WHERE position('\x416c657274696e67' in data) > 0) AS firing
     FROM alert_rule_state;"
```

Ожидается `evaluated` = 14, `firing` — сколько правил сейчас в состоянии
Alerting. Состояние лежит protobuf-блобом, поэтому читается поиском подстроки
`Alerting` в hex; читаемой колонки нет. Расхождение с числом правил в
`k8s/alerts.yaml` означает, что в Grafana попало лишнее (или потерялось нужное) —
сверять надо с `SELECT count(*) FROM alert_rule`.

**Ноль в `evaluated` означает, что ни одно правило не вычислилось** — при этом
`alert_rule` в базе будет полной, а UI покажет созданные правила. Так выглядел
баг с отсутствующим вложенным `datasource` в `model`.

Таблица `alert_instance` в Grafana 13 пустая и **не является признаком поломки**:
состояние правил переехало в `alert_rule_state`. Проверять `alert_instance` нельзя
— на ней самой alerts сломаны выглядят исправными.

Ошибки оценки видны и в логах:

```sh
kubectl logs deploy/grafana-deployment -n monitoring --since=10m | grep "Failed to evaluate rule"
```

Правила внутри одной группы вычисляются последовательно, поэтому одно сломанное
правило блокирует остальные: в логах будет только его uid. Это сбивает с
толку — кажется, что сломалось одно, а на деле не считается вся группа.

Проверка доставки без правки правил — временно поставить одному правилу
`for: 0s` и заведомо истинное условие, затем вернуть как было. Быстрее и без
риска оставить заведомо ложное правило-«canary» в `k8s/alerts.yaml`, но оно
не должно попасть в main.

Обновления правил доезжают обычным путём — `kubectl apply` пересобирает
ConfigMap, меняется его ResourceVersion, оператор пересчитывает
`checksum/secrets` и под перезапускается сам. Отдельный `rollout restart` не
нужен. Перечитывание провижининга без рестарта через Admin API у Grafana есть,
но не документировано здесь непроверенным: перед тем как на него ссылаться, его
надо открыть с сервис-аккаунтом и убедиться, что он отвечает.

## Развёртывание в Kubernetes

`k8s/grafana.yaml` — CR `Grafana`: версия образа, `GF_DATABASE_*`, креды через
`secretKeyRef`, probes, ресурсы и тома провижининга. Deployment, Service,
ServiceAccount, ConfigMap с `grafana.ini` и headless-Service для алертинга
создаёт `grafana-operator`; в репозитории их нет.

Ресурсы оператора получают суффикс к имени CR: `grafana-deployment`,
`grafana-service` (порт 3000), `grafana-alerting`, `grafana-sa`. Лейбл подов
оператор ставит `app: grafana` — поэтому NetworkPolicy в `platform/cnpg/`,
выпускающий доступ к Postgres, продолжает работать без правок.

Маршрут — `apps/grafana/k8s/route.yaml` (`Host(grafana…)` за
`oauth2-proxy` + `secure-headers` + `ratelimit-default`) на
`grafana-service:3000`; Gatus и vmagent ходят на тот же адрес.

CR применяется **после** установки `grafana-operator`: без CRD `Grafana`
невалиден, и Argo не ставит оператор и CR в одном приложении (см. комментарий
в `argocd/applications/cloudnative-pg.yaml`).

Откат: убрать CR и вернуть `k8s/grafana.deployment.yaml` и
`k8s/grafana.service.yaml` из истории git. Данные в Postgres не теряются —
они переживают оба Deployment.

## Проверка

```sh
curl --resolve grafana.${DOMAIN}:443:<node1-ip> \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://grafana.${DOMAIN}/
```

Ожидаемый ответ: `302` (redirect на oauth2-proxy). Health API напрямую:

```sh
kubectl exec deploy/grafana-deployment -- curl -fsS http://127.0.0.1:3000/api/health
```

Что Grafana подключена к Postgres, видно по логу старта (`database: postgres`)
и по отсутствию `grafana.db` в поде.

Ротация секрета проверяется так: сменить значение в Vault, дождаться синка VSO и
убедиться, что под перезапустился сам —

```sh
kubectl -n monitoring get pod -l app=grafana \
  -o jsonpath='{.items[0].metadata.annotations.checksum/secrets}'
```

Пока значение не меняли, аннотация содержит SHA ресурсов; после ротации она
меняется, и это признак рестарта без `rollout restart`.
