# Argo CD

GitOps-контроллер кластера: источник правды — `main`, root-приложение
раскатывает `Application` из `clusters/casa/`. Параметры установки — в
`bootstrap/argocd-values.yaml`: это отклонения от дефолтов чарта, а не манифесты
кластера.

## Вход

Панель Argo обслуживается `HTTPRoute` на собственном self-managed логине,
дальше OIDC через authentik. Middleware `oauth2-proxy` к нему **не подключен
намеренно**: forward auth поверх сгорает — ломает сессию Argo и его CLI.
`secure-headers` подключён, `ratelimit-default` нет: UI Argo постоянно опрашивает
API, и лимит 100/50 срабатывает при обычном просмотре синка.

`secure-headers` продублирован в каждом namespace, где его использует
`ExtensionRef`: ссылка в `HTTPRoute` ищет `Middleware` рядом с маршрутом, а не
в `traefik`. Оригинал — `clusters/casa/platform/traefik/manifests/oauth2-proxy.middleware.yaml`.

## Как Argo применяет манифесты

Режим применения задаётся **по юниту**, в `spec.syncPolicy.syncOptions` его
`app.yaml`. Глобального тумблера у Argo нет: ни среди флагов
`argocd-application-controller`, ни в `argocd-cmd-params-cm`, ни в `AppProject`.
На отдельный ресурс режим задаётся аннотацией
`argocd.argoproj.io/sync-options: ServerSideApply=true`, но это тот же выбор,
только ниже уровнем. Поэтому SSA стоит у всех юнитов.

Такой объект Argo применяет через `kubectl apply --server-side --force-conflicts`:
владение полями видно в `managedFields`, лимит аннотации
`last-applied-configuration` (262144 байта) не действует, а переход юнита с
client-side apply Argo доводит сам — миграцией менеджера полей
(`ClientSideApplyMigration`, включена по умолчанию). Поэтому `Force=true` для
перехвата владения не нужен: в Argo это другая опция (см. ниже).

Расхождение считается server-side diff'ом — `controller.diff.server.side: "true"`
в `bootstrap/argocd-values.yaml`. Argo делает dry-run применение и сравнивает
результат с живым объектом, поэтому то, что дописывают вебхуки операторов (у
`Cluster` CNPG — около сорока полей: `postgresql.parameters.*`, `probes`,
`startDelay`, `storage.resizeInUseVolumes` и прочее), расхождением не считается.
Без этого флага сравнение идёт «желаемое против живого», и такие поля пришлось бы
перечислять в `ignoreDifferences` — поэтому флаг включён раньше, чем юниты баз
перевели на SSA. Цена — dry-run на каждое сравнение; отдельному приложению,
которому dry-run не подходит, можно вернуть обычное сравнение compare-опцией
`ServerSideDiff=false`.

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
| 0 | `gateway-api`, `namespaces`, `priorityclasses` | то, без чего не создастся ничто: CRD Gateway API, namespace'ы, классы приоритетов |
| 10 | операторы, их CRD и хранилище: `cert-manager`, `cloudnative-pg`, `mariadb-operator`, `vault-secrets-operator`, `victoria-metrics-operator`, `vpa`, `trivy-operator`, `elastic-operator`, `falco`, `longhorn`, `snapshot-controller`, `local-path-provisioner`, `local-storage` | CR нельзя применить раньше CRD, а PVC — раньше CSI и класса хранилища |
| 20 | платформа и то, от чего зависят приложения: `traefik`, `vault`, `monitoring`, UI, `dns01-webhook`, `technitium` | секреты из Vault нужны базам, Gateway — маршрутам, зона DNS — выпуску wildcard-сертификата |
| 30 | кластеры баз: `cnpg`, `mariadb` | базы нужны приложениям, но не друг другу |
| 40 | приложения | последними: потребителей у них нет |

Внутри `cnpg` и `mariadb` та же логика: секреты ролей (0) → кластер (10) → база
(20) → пользователь и его права (20). База применяется только после того, как
кластер стал `Healthy`, — это закрывает грабли «`Database`, увидевший
отсутствующий кластер, залипает в `applied: false`» (см. `../cnpg/RUNBOOK.md`).

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
`bootstrap/argocd-values.yaml`), а у `argoproj.io/Application` с Argo 1.8 её в
поставке нет. Поэтому `Application` считается применённым сразу после apply:
волны упорядочивают создание приложений, но не их готовность, а недостающие
зависимости — CR без CRD, под без секрета — добираются `retry` у приложения и
ретраями самих операторов.

Установка, бутстрап, обновление релиза, правила проектов и разборы — в
`RUNBOOK.md`.
