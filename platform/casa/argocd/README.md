# Argo CD

GitOps-контроллер кластера: источник правды — `main`, root-приложение
раскатывает `Application` из `clusters/casa/argocd/`. Параметры установки — в
`platform/casa/argocd/values.yaml`: это отклонения от дефолтов чарта, а не манифесты
кластера.

## Управление собой

Argo применяет свой чарт тем же способом, что и остальные юниты: спека
`clusters/casa/argocd/platform/argocd.yaml`, значения рядом с юнитом. Первичная
установка всё равно ручная — контроллер
не поставит себя в пустом кластере, — но дальше настройки живут в git: правка
`values.yaml`, коммит, синк. Дрейф настроек контроллера перестаёт быть невидимым,
а `helm upgrade` из бутстрапа становится одноразовым шагом (после адопции релиз
«забывают», иначе Helm и Argo начнут конкурировать).

Плата за это — самозамыкание: ошибка в юните отрежет доступ к GitOps. Поэтому у
приложения `Prune=false` (Argo ничего своего не удалит), а восстановление
описано в `RUNBOOK.md` и в `clusters/casa/argocd/bootstrap/README.md`: revert коммита и синк, а если
сломан сам контроллер — `helm install` с values из юнита.

Секрет `argocd-secret` исключён из сравнения (`ignoreDifferences` на `/data`):
`admin.password` и `server.secretkey` дописывает сам Argo в рантайме, в git их нет
по определению.

## Вход

Панель Argo обслуживается `HTTPRoute` на собственном self-managed логине,
дальше OIDC через authentik. Middleware `oauth2-proxy` к нему **не подключен
намеренно**: forward auth поверх сгорает — ломает сессию Argo и его CLI.
`secure-headers` подключён, `ratelimit-default` нет: UI Argo постоянно опрашивает
API, и лимит 100/50 срабатывает при обычном просмотре синка.

`secure-headers` продублирован в каждом namespace, где его использует
`ExtensionRef`: ссылка в `HTTPRoute` ищет `Middleware` рядом с маршрутом, а не
в `traefik`. Оригинал — `platform/casa/traefik/manifests/oauth2-proxy.middleware.yaml`.

## Как Argo применяет манифесты

Режим применения задаётся **по юниту**, в `spec.syncPolicy.syncOptions` его
спеки. Глобального тумблера у Argo нет: ни среди флагов
`argocd-application-controller`, ни в `argocd-cmd-params-cm`, ни в `AppProject`.
На отдельный ресурс режим задаётся аннотацией
`argocd.argoproj.io/sync-options: ServerSideApply=true`, но это тот же выбор,
только ниже уровнем. Так SSA стоит у всех юнитов, кроме юнитов с базами.

SSA применяет объект через `kubectl apply --server-side --force-conflicts`:
владение полями видно в `managedFields`, лимит аннотации
`last-applied-configuration` (262144 байта) не действует, а переход юнита с
client-side apply Argo доводит сам — миграцией менеджера полей
(`ClientSideApplyMigration`, включена по умолчанию). Поэтому `Force=true` для
перехвата владения не нужен: в Argo это другая опция (см. ниже).

**Исключение — юниты, владеющие CR с admission-дефолтами** (это `cnpg` с общим
кластером и пятеро с выделенными базами: `immich`, `zitadel`, `dawarich`,
`seafile`, `uptime-kuma`). Они на client-side apply и с
`argocd.argoproj.io/compare-options: ServerSideDiff=false`. Оба оператора
дописывают значения в `spec` на admission (CNPG — `api/v1/cluster_defaults.go`,
`func (r *Cluster) Default()` и guard-вебхук; mariadb-operator — вебхук
`vmariadb-v1alpha1.kb.io`) и часть полей объявляют неизменяемыми
(`rootEmptyPassword`, `storage.ephemeral`). При SSA Argo забирает владение этими
полями себе и дальше считает их «своими, но в git не объявленными», то есть
пытается удалить на каждом sync: у CNPG вебхук возвращает их обратно (вечный
`OutOfSync`), у MariaDB неизменяемые отклоняют патч целиком (`SyncFailed`).
Классическое трёхстороннее сравнение по `last-applied-configuration` такие поля
поглощает, поэтому базам и нужен client-side apply. Если SSA для них понадобится,
условие — `ignoreDifferences` на каждое такое поле (у `Cluster` их около сорока)
плюс `RespectIgnoreDifferences`; `/spec/postgresql/parameters` целиком
игнорировать нельзя — там же лежат наши параметры, например `wal_keep_size`.

Расхождение по умолчанию считается server-side diff'ом —
`controller.diff.server.side: "true"` в `platform/casa/argocd/values.yaml`: Argo
делает dry-run применение и сравнивает результат с живым объектом, поэтому то,
что дописывают admission-вебхуки, расхождением не считается. Цена — dry-run на
каждое сравнение; юниту, которому он не подходит, сравнение возвращается
compare-опцией `ServerSideDiff=false` (так сделано у баз). Ограничение, о которое
легко споткнуться: server-side diff меняет способ **сравнения**, но не
**владение** полями — от удаления полей, которые Argo себе присвоил, он не
спасает.

Исключения из сравнения пишем JSON Pointer'ами (`jsonPointers`), а не
`jqPathExpressions`: указатели переносимы (тот же формат у `spec.ignore` во Flux
и у `kubectl`), и их достаточно везде, кроме wildcard'ов по массивам — там jq
неизбежен, но таких правил у нас нет: дефолты apiserver поглощает server-side
diff.

`Replace=true` и `Force=true` — не режимы применения, а `kubectl replace` и
`delete/create`, то есть пересоздание ресурса. Для `Cluster` и `MariaDB` это
означает потерю PVC, поэтому в юнитах баз они не используются.

Если в `argocd app diff` появились строки `<` на полях, которых нет в git, это
обычно след живого применения: `kubectl get -o yaml | kubectl apply -f -` кладёт
дефолты оператора в `last-applied-configuration`, и Argo пытается их удалить.
Неизменяемые поля при этом отбивает вебхук, и патч отклоняется целиком, так что
не доезжают даже аннотации. Лечится снятием аннотации у объекта, после чего
первый apply двусторонний (удалять ему нечего), а Argo перезаписывает аннотацию
своим рендером из git:

```sh
kubectl -n <ns> annotate <kind> <name> kubectl.kubernetes.io/last-applied-configuration-
```

## Порядок применения

Порядок задают `argocd.argoproj.io/sync-wave` — на спеках `Application` и на
объектах внутри юнитов баз. Шаг 10, чтобы стадию можно было вставить между
соседними, не перенумеровывая всё дерево.

| Волна | Что применяется | Почему здесь |
|---|---|---|
| 0 | `gateway-api`, `priorityclasses` | то, без чего не создастся ничто: CRD Gateway API и классы приоритетов |
| 10 | операторы, их CRD и хранилище: `cert-manager`, `cloudnative-pg`, `mariadb-operator`, `vault-secrets-operator`, `victoria-metrics-operator`, `vpa`, `trivy-operator`, `elastic-operator`, `falco`, `longhorn`, `snapshot-controller`, `local-path-provisioner`, `local-storage` | CR нельзя применить раньше CRD, а PVC — раньше CSI и класса хранилища |
| 20 | платформа и то, от чего зависят приложения: `traefik`, `vault`, `monitoring`, UI, `dns01-webhook`, `technitium` | секреты из Vault нужны базам, Gateway — маршрутам, зона DNS — выпуску wildcard-сертификата |
| 30 | кластеры баз: `cnpg` | базы нужны приложениям, но не друг другу |
| 40 | приложения | последними: потребителей у них нет |

Namespace'ы едут вместе со своими юнитами: namespace объявляет тот юнит, в
котором лежит его `Application` (`docs/adr/0011`), и своей волны у них больше
нет. Порядок внутри синхронизации это выдерживает: Argo сортирует ресурсы по
kind, и `Namespace` в этом списке первый — раньше и CRD, и рабочих нагрузок
(`gitops-engine`, `pkg/sync/sync_tasks.go`).

Внутри юнита волна — не только порядок, но и ожидание: Argo держит следующую
волну, пока ресурсы предыдущей не станут `Healthy`. Поэтому волны внутри есть
только у `cnpg` с общим кластером: секреты ролей (0) → кластер (10) → базы (20),
и база применяется лишь после того, как кластер стал `Healthy` — это закрывает
грабли «`Database`, увидевший отсутствующий кластер, залипает в `applied: false`»
(см. `../cnpg/RUNBOOK.md`).

У выделенных кластеров и MariaDB в юнитах сервисов волн **нет** намеренно: вместе
с базой в юните живут рабочие нагрузки, а ожидание их готовности заблокировало бы
применение объектов базы — синхронизация уходила бы в retry, и база молча не
создавалась (так и вышло при переезде: `Deployment onlyoffice` не прошёл
`progressDeadline` и держал волну). Порядок «кластер → база» там дают сортировка по
kind и ретраи операторов, а залипшую `Database` видно в UI: health-проверка CR
показывает `Progressing`, пока `status.applied` не станет true.

Новый юнит встаёт в волну по ближайшему потребителю: если без него не создастся
чужой объект, он идёт раньше. Гейта на принадлежность к волне нет намеренно:
правило читается отсюда, а ошибка проявляется отказом создания, который добирают
`retry` приложения и ретраи самих операторов (см. ниже).

При удалении порядок обратный: prune идёт от старших волн к младшим, то есть
приложения раньше баз, а базы — раньше операторов.

Волна задаёт порядок **применения**, а не ожидание готовности. Argo ждёт
`Healthy` у ресурсов волны, только когда у ресурса есть health-проверка: у
`Deployment`, `PVC` и прочих встроенных она есть, у CR — только если задан
`resource.customizations.health.*` (для CNPG и MariaDB он в
`platform/casa/argocd/values.yaml`), а у `argoproj.io/Application` с Argo 1.8 её в
поставке нет. Поэтому `Application` считается применённым сразу после apply:
волны упорядочивают создание приложений, но не их готовность, а недостающие
зависимости — CR без CRD, под без секрета — добираются `retry` у приложения и
ретраями самих операторов.

Установка, бутстрап, обновление релиза, правила проектов и разборы — в
`RUNBOOK.md`.
