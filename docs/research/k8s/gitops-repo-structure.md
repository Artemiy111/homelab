# Структура GitOps-репозитория для Kubernetes: каноны и раскладка для этого homelab

Дата проверки: 2026-09-18.

## Короткий вывод

1. **Официальный канон Flux — монорепо из трёх верхних каталогов**
   `clusters/`, `infrastructure/` (у нас логичнее `platform/`), `apps/`, где
   `clusters/<кластер>` держит только Flux-объекты, а внутри каждой группы
   `base` + оверлеи по средам
   ([Flux: Ways of structuring your repositories](https://fluxcd.io/flux/guides/repository-structure/)).
   Разделение `apps` и инфраструктуры существует ровно ради порядка применения:
   сначала платформенные контроллеры, потом приложения.

2. **Группировка — по namespace (= владению), не по средам.** Это уже зашито в
   `CONTEXT.md` и `docs/adr/0001-namespace-ownership.md`: namespace — единица
   владения, среды разводятся отдельными кластерами/машинами. Ни Flux, ни Argo
   не спорят с этим: оба маппят «приложение» на namespace.

3. **Внешний чарт в Flux — это `HelmRelease` + маленький `values.yaml` с
   отклонениями, а не `kustomize helmCharts`.** Kustomize официально заявляет,
   что helm-inflation — «ограниченное подмножество» без авторизации в приватных
   реестрах и без полного набора фич Helm
   ([Kustomize: helmCharts](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/helmcharts/)).
   `HelmRelease` же даёт настоящий Helm-релиз, drift detection, `valuesFrom`,
   `dependsOn` ([Flux: Manage Helm Releases](https://fluxcd.io/flux/guides/helmreleases/),
   [HelmRelease API](https://github.com/fluxcd/helm-controller/blob/main/docs/spec/v2/helmreleases.md)).

4. **Автопоиска приложений в Flux нет и это осознанно.** `Kustomization.spec.path`
   — это один путь к каталогу, без wildcard; каждый апп указывается явно
   ([Flux: Kustomization `path`](https://fluxcd.io/flux/components/kustomize/kustomizations/)).
   У Argo это закрывает ApplicationSet git-генератор, но у него есть цена:
   предупреждения о безопасности и «жадности» генератора
   ([Argo: Git Generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Git/),
   [Argo: ApplicationSet Security](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Security/)).
   Для ~60 апп явный список из одного `Kustomization` на сервис даёт
   per-app blast radius и понятный `flux tree`.

5. **Порядок применения:** у Flux — `spec.dependsOn` + `healthChecks`/`wait`
   ([Flux: Kustomization Dependencies](https://fluxcd.io/flux/components/kustomize/kustomizations/)),
   у Argo — sync-waves (`argocd.argoproj.io/sync-wave`) и фазы hooks
   ([Argo: Sync Phases and Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)).
   Раскладка `platform/controllers → platform/configs → apps` делает порядок
   явным в дереве, а не в аннотациях.

6. **Argo CD → Flux мигрируется по одному приложению, с передачей владения.**
   Два контроллера на одном объекте — гарантированный пинг-понг
   (`k8s/argocd/README.md`). Официального кросс-вендорного гайда миграции нет;
   механизмы подтверждены по отдельности: Argo трекает владельца аннотацией
   `argocd.argoproj.io/tracking-id`, а удаление Application можно сделать
   «осиротить» ресурсы; Flux по умолчанию вправе взять ownership существующих
   ресурсов при Helm install/upgrade ([Argo: Resource Tracking](https://argo-cd.readthedocs.io/en/stable/user-guide/resource_tracking/),
   Flux `.install.disableTakeOwnership`, [FluxRelease API](https://github.com/fluxcd/helm-controller/blob/main/docs/spec/v2/helmreleases.md)).
   Сама процедура — синтез, см. «Не подтверждённые утверждения».

**Рекомендация для этого репозитория (кратко):** ввести `clusters/k0s/` и
`platform/{sources,controllers,configs}/`, оставить `apps/<сервис>/` как единицу
владения, но заменить `k8s/`-манифесты на `HelmRelease` + `values.yaml` (только
отклонения) + `route.yaml` + `sealedsecret.yaml`, а старый `apps/<сервис>/k8s/`
и `compose.yaml`/`secrets.enc.env` выводить по мере миграции. Детали и дерево —
в разделе [9](#9-рекомендованная-раскладка-для-этого-репозитория).

---

## Текущее состояние репозитория (контекст)

| Слой | Где сейчас | Кем управляется |
| --- | --- | --- |
| Платформенные манифесты | `k8s/<компонент>/` (traefik, longhorn, cnpg, local-storage, sealed-secrets) | в основном `kubectl apply` вручную |
| Платформенные Helm-компоненты | `k8s/argocd/*.yaml` (Application'ы с `valuesObject` в спеке) | Argo CD (пробный стенд) |
| Приложения | `apps/<сервис>/k8s/` — plain-манифесты эпохи Compose | вручную |
| Приложения на чартах | пока нет; `k8s/cnpg/README.md` фиксирует цель (immich, forgejo) | — |
| Секреты доставка | `apps/<сервис>/k8s/sealedsecret.yaml` | sealed-secrets controller |
| Секреты реестр | `apps/<сервис>/secrets.enc.env` + `.sops.yaml` | SOPS+age вне кластера |
| Legacy | `apps/<сервис>/{compose.yaml,init.sh,config.env}` | выводится из эксплуатации |

Требования владельца: один узел k0s, GitOps, целевой инструмент Flux, много
приложений из **внешних Helm-чартов с owner-supplied values**, секреты —
SealedSecrets, реестр — SOPS+age+vals.

---

## 1. Канонические раскладки: что рекомендуют сами проекты

### 1.1. Flux

Официальный гид «[Ways of structuring your repositories](https://fluxcd.io/flux/guides/repository-structure/)»
перечисляет четыре модели:

| Модель | Структура | Когда |
| --- | --- | --- |
| **Monorepo** | `apps/{base,production,staging}`, `infrastructure/{base,production,staging}`, `clusters/{production,staging}` | один репозиторий, несколько сред, trunk-based |
| **Repo per environment** | отдельный репо на прод | прод-доступ нужно ограничить от staging-разработчиков |
| **Repo per team** | `teams/`, `infrastructure/`, `clusters/`; у команды свой `apps/{base,prod,staging}` | платформенная команда + dev-команды (multi-tenancy) |
| **Repo per app** | в конфиг-репо `GitRepository` + `Kustomization`/`HelmRelease` ссылаются на чарт/манифесты из репо приложения | конфиг отдельно от исходников |

Референсный пример monorepo — [fluxcd/flux2-kustomize-helm-example](https://github.com/fluxcd/flux2-kustomize-helm-example):

```
├── apps
│   ├── base            # HelmRelease с общими values (namespace, repository)
│   ├── production      # Kustomize-патч с прод-values
│   └── staging         # Kustomize-патч со staging-values
├── infrastructure
│   ├── configs         # CR: ClusterIssuer, Gateway, NetworkPolicy
│   └── controllers     # OCIRepository + HelmRelease контроллеров
└── clusters
    ├── production      # apps.yaml, infrastructure.yaml, artifacts.yaml
    └── staging
```

Ключевые приёмы из README примера:

- `apps/base/<app>/` содержит общий `HelmRelease` (и `HelmRepository`/`OCIRepository`),
  а `apps/<env>/` — только Kustomize-патч с отличиями (домены, версии чарта,
  `test.enable`). Это ровно «дефолты чарта vs deploy-override».
- `clusters/<env>/infrastructure.yaml` использует `dependsOn`, чтобы CRD
  контроллеров появились раньше CR: «with `dependsOn` we tell Flux to first
  install or upgrade the controllers and only then the configs».
- `clusters/<env>/apps.yaml` с `dependsOn: infra-configs`, `wait: true`,
  `prune: true`.
- Начиная с Flux 2.7 `ArtifactGenerator`/`ExternalArtifact` умеют «разрезать»
  монорепо на независимо синкаемые артефакты, чтобы коммит вне `apps/` не
  триггерил пересборку приложений (README примера, раздел «Clusters»).

Пример multi-tenancy — [fluxcd/flux2-multi-tenancy](https://github.com/fluxcd/flux2-multi-tenancy):

- Fleet-репо платформенной команды: `clusters/`, `policies/`, `tenants/`;
  тенант-репо повторяет `base` + `staging`/`production`.
- Порядок задаётся цепочкой Kustomization: `policies` → `tenants` (через
  `dependsOn`).
- Изоляция — namespace + `serviceAccountName` + multi-tenancy lockdown
  (`--no-cross-namespace-refs`, default service account).

### 1.2. Argo CD

- [Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
  начинаются с двух правил: **держать конфиг в отдельном репозитории от
  исходников** и **пиновать ревизии** (не `HEAD`, не tagless remote base), иначе
  манифест «меняет смысл» без изменений в своём git.
- [Cluster Bootstrapping](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
  рекомендует **ApplicationSet + cluster generator** как основной путь, а
  **app-of-apps** — как альтернативу с пометкой «App of Apps is an admin-only
  tool» (права создавать `Application` в произвольных Project'ах = админские).
- Пример app-of-apps ([argocd-example-apps/apps](https://github.com/argoproj/argocd-example-apps/tree/master/apps))
  — один корневой `Application`, чьи манифесты суть другие `Application`.
- Helm-пример bootstrap — «chart of charts»: `Chart.yaml` + `templates/<child>.yaml`
  (по одному `Application` на дочерний апп) + `values.yaml`.
- Каталог [argocd-example-apps](https://github.com/argoproj/argocd-example-apps)
  разложен «по фичам» (`guestbook`, `helm-guestbook`, `sync-waves`, `applicationset`),
  то есть как демо-песочница, а не как продакшн-раскладка.

**Вывод:** канон Flux (`clusters` + `infrastructure` + `apps`) прямо
поддерживает требуемый порядок «платформа → приложения» структурно, а Argo
выражает тот же порядок через sync-waves и app-of-apps. Для нашего репозитория
это аргумент в пользу Flux-раскладки.

---

## 2. Где хранить values внешних чартов

| Вопрос | Ответ | Источник |
| --- | --- | --- |
| Где значения деплоя? | В `apps/<app>/values.yaml` (или в Kustomize-патче оверлея) — **только отклонения** от дефолтов чарта | [flux2-kustomize-helm-example](https://github.com/fluxcd/flux2-kustomize-helm-example) (base + patch) |
| Где дефолты чарта? | Не копировать. Дефолты — в самом чарте; репо хранит override | тот же пример: `apps/base` — общее, `apps/<env>` — отличия |
| Как передать values? | три способа: `.spec.values` (inline), `.spec.valuesFrom` (ConfigMap/Secret), `.spec.chart.spec.valuesFiles` (файлы внутри чарта) | [Flux HelmRelease API](https://github.com/fluxcd/helm-controller/blob/main/docs/spec/v2/helmreleases.md) |
| Порядок merge | `valuesFrom` (в порядке списка) → inline `values` поверх; `targetPath` перекрывает всё до него | там же |
| Секретные values | `valuesFrom` → Secret; Secret генерируется Kustomize `secretGenerator` из SOPS-файла | [Flux: Manage Helm Releases, «Refer to values in Secret generated with Kustomize and SOPS»](https://fluxcd.io/flux/guides/helmreleases/) |
| Общие values между чартами | Helm `global` работает **только в дереве одного чарта** (parent→subchart), между независимыми `HelmRelease` не работает | [Helm: Subcharts and Global Values](https://helm.sh/docs/chart_template_guide/subcharts_and_globals/) |

Важное следствие про shared values: поскольку `global` не переносится между
отдельными релизами, «общие values» на уровне репозитория — это задача GitOps-слоя,
а не Helm. Рабочие варианты:

1. **Kustomize `components`/`patches` + `replacements`** — один источник (например,
   `platform/configs/common-values`), который патчит `spec.values` каждого
   `HelmRelease`. Работает ровно как base+patch в канон-примере.
2. **`valuesFrom` на общий ConfigMap в том же namespace** — но ConfigMap
   namespaced, поэтому либо копия на namespace, либо reflector. Это уже
   задокументированная в репо проблема `homelab-config`
   (`k8s/homelab-config/configmap.yaml`).
3. **Post-build substitution** Flux (`Kustomization.spec.postBuild.substitute`) —
   подстановка общих переменных в собранные манифесты, включая значения
   `HelmRelease` (упомянут в [Flux Kustomization](https://fluxcd.io/flux/components/kustomize/kustomizations/)).

Для нашего масштаба рекомендация — вариант 1 с одним общим фрагментом
(домен, TZ, внешний IP), а не дублирование values по каждому сервису.

### Wrapper/umbrella charts

- Helm документирует **subcharts** и вызов «parent overrides subchart values»
  ([Helm docs](https://helm.sh/docs/chart_template_guide/subcharts_and_globals/)).
- Argo CD показывает поддерживаемый паттерн `helm-dependency` для кастомизации
  OTS-чарта ([argocd-example-apps/helm-dependency](https://github.com/argoproj/argocd-example-apps/tree/master/helm-dependency)).
- **Library charts** — отдельный тип (`type: library`): переиспользуемые шаблоны,
  не устанавливаются сами ([Helm: Library Charts](https://helm.sh/docs/topics/library_charts/)).

Вывод: wrapper-чарт нужен, только если к внешнему чарту надо **добавить
собственные шаблоны** (или использовать library-хелперы). Если меняются только
values — wrapper не нужен: снаружи есть `valuesFrom`/`values`/Kustomize-патч.
Утверждение «wrapper — антипаттерн» вендоры не формулируют (см. «Не
подтверждённые утверждения»).

---

## 3. Группировка: namespace / среда / кластер / плоско

| Ось | Что говорит первоисточник | Применимость здесь |
| --- | --- | --- |
| **По namespace (владение)** | Flux multi-tenancy: «trust boundary of a tenant is the Kubernetes namespace» | ✅ совпадает с `docs/adr/0001` |
| **По среде** | Flux monorepo: оверлеи `production`/`staging` внутри одного кластера; Argo: sync-waves | ❌ `CONTEXT.md`: среды — отдельные кластеры, не namespace'ы |
| **По кластеру** | `clusters/<name>/` в обоих канонах | ✅ один кластер сейчас, имя `k0s`; второй = новый каталог |
| **Плоско** | Argo best practices не запрещают, но теряются границы и порядок | ❌ для 60 сервисов не масштабируется по blast radius |

Multi-tenancy паттерн Flux (для понимания границ): namespace + ServiceAccount +
impersonation + `--no-cross-namespace-refs=true` + default service account
([Flux: multi-tenancy](https://fluxcd.io/flux/security/best-practices/)).
Для одного оператора lockdown не обязателен, но структура «namespace = единица»
та же.

**Вывод:** группировать по namespace/сервису; каталог кластера держать верхним
уровнем (`clusters/k0s/`), чтобы появление второй среды не потребовало
переписывать дерево.

---

## 4. Автопоиск приложений vs явный список

### Argo CD: ApplicationSet

- **Git directory generator** обходит каталоги по wildcard (`path: <dir>/*`) и
  создаёт `Application` на каждый каталог; есть `exclude` (правила исключения
  приоритетнее включения), `path.basename`, `basenameNormalized`
  ([Argo: Git Generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Git/)).
- **Git file generator** читает JSON/YAML-файлы; документация сама предупреждает:
  «default behavior ... is very greedy»
  ([Argo: Git File Generator Globbing](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Git-File-Globbing/)).
- ApplicationSet можно создавать только админам; при шаблонном `project`
  источник истины (git-репо) обязан контролироваться админами
  ([Argo: ApplicationSet Security](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Security/)).

### Flux: автопоиска нет

- `Kustomization.spec.path` — «path to the directory ... containing
  `kustomization.yaml`» — **один путь, без wildcard**. Автообнаружения каталогов
  с приложениями не существует
  ([Flux: Kustomization path](https://fluxcd.io/flux/components/kustomize/kustomizations/)).
- Композиция — вложенные `Kustomization` через `dependsOn`, а не генератор.
- `ArtifactGenerator` (2.7) режет монорепо на артефакты, но список путей всё
  равно задаётся явно.

| Критерий | Argo ApplicationSet (git generator) | Flux (явный список Kustomization) |
| --- | --- | --- |
| Добавить апп | положить каталог → Application появится сам | добавить `Kustomization` |
| Удалить апп | удалить каталог → Application исчезнет | удалить `Kustomization` |
| Риск | «жадный» генератор создаёт лишнее; шаблонный `project` — вектор атаки | нет скрытой генерации; всё в диффе |
| Blast radius | один ApplicationSet растит/удаляет пачкой | per-app `prune`/`wait` |
| Масштаб | хорошо для «много похожих» (per-cluster, per-team) | boilerplate растёт линейно |

**Вывод для репо:** ~60 приложений — это не тот масштаб, где автогенерация
окупает риски. Явный `Kustomization` на сервис даёт `flux get kustomizations`
как понятную панель и per-app prune. Boilerplate можно генерировать в CI из
списка каталогов, но набор остаётся явным и ревьюится.

---

## 5. Авторские чарты vs внешние; монорепо vs чарт-репо

| Что | Где | Источник |
| --- | --- | --- |
| Внешний чарт, только values | `HelmRelease` в репо конфига, чарт из `HelmRepository`/`OCIRepository` | [Flux helmreleases](https://fluxcd.io/flux/guides/helmreleases/) |
| Авторские манифесты | каталог приложения, `Kustomization` | [Flux repository structure](https://fluxcd.io/flux/guides/repository-structure/) |
| Авторский чарт | либо в монорепо, либо отдельный чарт-репо | там же, «Repo per app» |
| Общие шаблоны | library chart (`type: library`) | [Helm: Library Charts](https://helm.sh/docs/topics/library_charts/) |

- Один репозиторий для конфигов **и** авторских чартов — нормально, пока чарты
  немногочисленны; Flux в режиме `GitRepository` + `path` умеет строить чарт из
  подкаталога (`chart: ./charts/podinfo`)
  ([Flux: Manage Helm Releases](https://fluxcd.io/flux/guides/helmreleases/)).
- Отдельный чарт-репо нужен, если чарт переиспользуется вне этого кластера или
  публикуется. Для homelab это преждевременно.
- Wrapper-чарт — только под добавление шаблонов, не под values (см. раздел 2).

---

## 6. Источники чартов и пинование версий

| Механизм Flux | Когда | Источник |
| --- | --- | --- |
| `HelmRepository` + `HelmRelease.chart.spec` | HTTP/S Helm-репо; поддерживает semver-селектор версии | [Flux helmreleases](https://fluxcd.io/flux/guides/helmreleases/) |
| `OCIRepository` + `HelmRelease.chartRef` | OCI-чарты (`oci://...`), можно пиновать `tag`/`digest`, верификация подписей | [Flux: OCIRepository](https://fluxcd.io/flux/components/source/ocirepositories/), [HelmRelease API](https://github.com/fluxcd/helm-controller/blob/main/docs/spec/v2/helmreleases.md) |
| `GitRepository` + `chart.spec.chart: ./path` | чарт лежит в git | [Flux helmreleases](https://fluxcd.io/flux/guides/helmreleases/) |

Пинование:

- Argo best practices: использовать tag/commit SHA, а не `HEAD` и не
  плавающий remote base ([Argo Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)).
- Flux допускает semver-диапазоны (`>=1.0.0`, `1.x`) и это удобно для
  автообновления, но для воспроизводимости лучше пиновать точную версию, а
  обновление делать коммитом (Renovate/image automation), чтобы изменение было
  в диффе GitOps-репо.
- `OCIRepository` с `ref.digest` — самый строгий пин; при `semver` Flux
  отслеживает новый digest и сам делает upgrade
  ([HelmRelease API](https://github.com/fluxcd/helm-controller/blob/main/docs/spec/v2/helmreleases.md)).

---

## 7. Порядок применения: infrastructure → apps

| | Argo CD | Flux |
| --- | --- | --- |
| Механизм | `argocd.argoproj.io/sync-wave` (int, по умолчанию 0, отрицательные допустимы), фазы `PreSync`/`Sync`/`PostSync`/`SyncFail`/`PostDelete` | `Kustomization.spec.dependsOn` + `healthChecks`/`wait`; `HelmRelease.spec.dependsOn` |
| Гранулярность | внутри одного Application задержка 2с между волнами | между Kustomization/HelmRelease, до `Ready` зависимости |
| Дерево | Application ресурсы, порядок в аннотациях | `flux tree kustomization`, порядок в `dependsOn` |
| Prune | волны в обратном порядке | garbage collection по `.status.inventory` |

Источники: [Argo Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/),
[Flux Kustomization Dependencies](https://fluxcd.io/flux/components/kustomize/kustomizations/),
[Flux HelmRelease API](https://github.com/fluxcd/helm-controller/blob/main/docs/spec/v2/helmreleases.md).

Практическое следствие для репо: порядок «оператор CNPG → CRD → `Cluster` → `Database`»,
который в `k8s/cnpg/README.md` держится ручной последовательностью `kubectl apply`,
в Flux выражается структурно:

```
platform/controllers  (CNPG operator HelmRelease, sealed-secrets, traefik, ...)
        │ dependsOn + healthChecks
        ▼
platform/configs      (namespaces, StorageClass, общий Cluster `shared`, ...)
        │ dependsOn
        ▼
apps                  (HelmRelease + Database + SealedSecret по сервисам)
```

Замечание про namespace: `targetNamespace` не создаёт namespace автоматически,
он должен существовать или быть в том же Kustomization
([Flux Kustomization](https://fluxcd.io/flux/components/kustomize/kustomizations/)).
Поэтому `namespace.yaml` сервиса должен ехать в `platform/configs` (или первым
документом в каталоге аппа).

---

## 8. Сосуществование Argo CD и Flux во время миграции

Два контроллера, ведущие один объект к разным desired state, дают пинг-понг
(это уже зафиксировано в `k8s/argocd/README.md`). Инвариант миграции: **у
каждого кластерного объекта ровно один владелец в каждый момент**.

Подтверждённые механизмы:

- Argo опознаёт «свои» ресурсы по аннотации `argocd.argoproj.io/tracking-id`
  (метод `annotation` по умолчанию) или по label `app.kubernetes.io/instance`
  (метод `label`); есть `installationID` для нескольких Argo на кластере
  ([Argo: Resource Tracking](https://argo-cd.readthedocs.io/en/stable/user-guide/resource_tracking/)).
- Удаление `Application` можно сделать некаскадным (orphan), чтобы оставить
  managed-ресурсы в кластере
  ([Argo: Cluster Bootstrapping / deleting apps](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/),
  `argocd app delete --cascade` в `k8s/argocd/README.md`).
- Flux `Kustomization.spec.suspend` останавливает reconcile (drift, prune),
  `HelmRelease` — тоже ([Flux Kustomization](https://fluxcd.io/flux/components/kustomize/kustomizations/)).
- Flux по умолчанию **не** отключает takeover существующих ресурсов при
  Helm install/upgrade (`.spec.install.disableTakeOwnership` / `.upgrade.disableTakeOwnership`
  по умолчанию `false`), то есть `HelmRelease` вправе принять ownership
  ([HelmRelease API](https://github.com/fluxcd/helm-controller/blob/main/docs/spec/v2/helmreleases.md)).

Предлагаемая последовательность (синтез, см. оговорки):

1. Установить Flux и забутстрапить **отдельный** путь, не пересекающийся с Argo:
   `flux bootstrap git --path=clusters/k0s`. `flux-system/` Flux управляет сам.
2. Сначала перевести **свой** Flux-контур (`platform/controllers`,
   `platform/configs`) — Argo эти объекты сейчас почти не трогает (он ведёт
   `k8s/argocd/*.yaml`).
3. Для каждого Argo Application по очереди:
   - `argocd app set <app> --sync-policy none` (выключить автосинк),
     чтобы Argo перестал исправлять дрейф;
   - `argocd app delete <app> --cascade=orphan` — ресурсы остаются;
   - добавить `Kustomization`/`HelmRelease` в Flux и дать ему принять объекты;
   - проверить `flux get kustomizations`, `kubectl get ... -o yaml | grep tracking-id`
     (убедиться, что stale-аннотация не мешает; при необходимости снять).
4. Когда все объекты под Flux — `helm uninstall argocd` + удалить его CRD
   (как в `k8s/argocd/README.md`).
5. Никогда не указывать обоим контроллерам один git-путь и не давать Argo
   `selfHeal` на объект, которым уже владеет Flux.

---

## 9. Рекомендованная раскладка для этого репозитория

### 9.1. Дерево

```
.
├── clusters/
│   └── k0s/                       # один кластер; второй = clusters/<имя>/
│       ├── flux-system/           # пишет flux bootstrap, руками не правим
│       ├── platform.yaml          # Kustomization → ./platform/configs,
│       │                          #   dependsOn platform-controllers
│       └── apps/                  # по одному Flux Kustomization на сервис
│           ├── forgejo.yaml
│           ├── immich.yaml
│           └── ...
│
├── platform/
│   ├── sources/                   # HelmRepository/OCIRepository, ns flux-system
│   ├── controllers/               # HelmRelease контроллеров: CNPG, ECK,
│   │                              #   sealed-secrets, Traefik, Longhorn,
│   │                              #   snapshot-controller, local-path
│   └── configs/                   # namespaces, StorageClass, VolumeSnapshotClass,
│                                  #   ClusterIssuer, общий CNPG `shared`
│
├── apps/
│   └── <сервис>/                  # каталог = граница владения
│       ├── kustomization.yaml     # ресурсы + patches + secretGenerator
│       ├── namespace.yaml         # (или в platform/configs)
│       ├── helmrelease.yaml       # внешний чарт + sourceRef
│       ├── values.yaml            # ТОЛЬКО отклонения от дефолтов чарта
│       ├── sealedsecret.yaml      # доставка секретов
│       ├── route.yaml             # Traefik IngressRoute в namespace сервиса
│       ├── config.env             # legacy, публичные значения
│       └── secrets.enc.env        # legacy, SOPS-реестр
│
├── docs/  ansible/  scripts/  ...
```

### 9.2. Обоснование каждого решения

| Решение | Почему |
| --- | --- |
| `clusters/` верхним уровнем, один `k0s/` | Канон Flux; появление второй среды (по `CONTEXT.md` — отдельный кластер) = новый каталог, без переписывания |
| `platform/` вместо `infrastructure/` | Репозиторий уже называет это платформой и платформенными компонентами (`CONTEXT.md`, README) |
| `platform/{controllers,configs}` | Структурно решает задокументированную боль `k8s/cnpg/README.md` (оператор раньше CR); порядок виден в дереве |
| `platform/sources` | Общий `HelmRepository`/`OCIRepository` на апстрим, чтобы source-controller не тянул индекс по разу на каждый апп; один источник определений |
| `apps/<сервис>/` плоско, без `k8s/` | Каталог = единица владения (`docs/adr/0001`); внутри — всё «про сервис»: релиз, values, секрет, маршрут |
| `HelmRelease` вместо `kustomize helmCharts` | Настоящий Helm-релиз, drift detection, `valuesFrom`, `dependsOn`; helmCharts официально ограничен и без приватной авторизации |
| `values.yaml` = только отклонения | Паттерн base+override из канон-примера; в репо уже есть это правило у `k8s/argocd/values.yaml` |
| `route.yaml` в каталоге сервиса | IngressRoute namespaced, а namespace — граница владения; централизованный `k8s/traefik/` противоречит ADR 0001 |
| Один Flux `Kustomization` на сервис | Per-app prune/health, `flux tree` как карта; Flux не умеет wildcard, явный список — это осознанный компромисс |
| `sealedsecret.yaml` в каталоге сервиса | Delivery через SealedSecrets сохраняется; Flux применяет SealedSecret как обычный манифест, контроллер расшифровывает ([Flux: Sealed Secrets](https://fluxcd.io/flux/guides/sealed-secrets/)) |
| `secrets.enc.env` рядом | Реестр SOPS+age+vals из `config-secrets-templating.md`; в доставке не участвует, но остаётся расшифровываемым источником |

### 9.3. Скетчи манифестов

`clusters/k0s/platform.yaml`:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: platform-configs
  namespace: flux-system
spec:
  interval: 1h
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./platform/configs
  prune: true
  wait: true
  dependsOn:
    - name: platform-controllers
```

`clusters/k0s/apps/forgejo.yaml`:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: forgejo
  namespace: flux-system
spec:
  interval: 1h
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./apps/forgejo
  prune: true
  wait: true
  dependsOn:
    - name: platform-configs
```

`apps/forgejo/helmrelease.yaml` (эскиз; реальный чарт и поля версии —
из апстрима forgejo-helm):

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: forgejo
  namespace: forgejo
spec:
  interval: 1h
  chart:
    spec:
      chart: forgejo
      version: "<точная версия>"          # не диапазон: воспроизводимость
      sourceRef:
        kind: HelmRepository
        name: forgejo
        namespace: flux-system
  values:
    # Только отклонения от дефолтов чарта, каждое с причиной.
    # Встроенная БД выключается, хост — CNPG `shared-rw.databases` (см. ADR 0002).
    postgresql-ha:
      enabled: false
```

### 9.4. Как раскладка переживает миграцию Argo CD → Flux

| Фаза | Что происходит | Что в дереве меняется |
| --- | --- | --- |
| 0. Как сейчас | Argo (`k8s/argocd/*.yaml`, `valuesObject` в спеке) + ручной `kubectl apply` | — |
| 1. Bootstrap Flux | `flux bootstrap git --path=clusters/k0s` создаёт `clusters/k0s/flux-system/` | появляется `clusters/`, `platform/` |
| 2. Платформа под Flux | `platform/controllers`+`configs` берут операторы (CNPG, ECK, sealed-secrets, Traefik, Longhorn) | Argo-файлы `k8s/argocd/{cloudnative-pg,eck-operator,longhorn,snapshot-controller,local-path-provisioner,kube-state-metrics}.yaml` выводятся |
| 3. Приложения по одному | Для каждого сервиса: Argo app → `--sync-policy none` → `--cascade=orphan` → `HelmRelease`/`Kustomization` под Flux | `apps/<сервис>/k8s/` заменяется на `helmrelease.yaml`+`values.yaml`+`route.yaml`; `k8s/traefik/<сервис>.ingress*.yaml` переезжает в `apps/<сервис>/route.yaml` |
| 4. Снятие Argo | `helm uninstall argocd`, удаление CRD | `k8s/argocd/` удаляется целиком |
| 5. Чистка legacy | `compose.yaml`, `init.sh`, мёртвые `scripts/` | `secrets.enc.env` остаётся как реестр |

Раскладка выбрана так, чтобы **каждая фаза была отдельным PR'ом**: `clusters/`
и `platform/` можно завести, не трогая `apps/`; перевод приложения — один
каталог + один файл `clusters/k0s/apps/<сервис>.yaml`. Argo и Flux никогда не
смотрят на один путь: Argo-manifest'ы живут в `k8s/argocd/`, Flux — в
`clusters/`/`platform/`/`apps/`.

---

## 10. Антипаттерны структуры GitOps-репозитория

Подтверждённые первоисточниками:

1. **Конфиг в репозитории исходников приложения.** Прямо не рекомендуется Argo
   ([Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)):
   шумный аудит, лишние CI-триггеры, размытие доступа.
2. **Плавающие ревизии** — `HEAD`, tagless remote base Kustomize. Argo:
   манифест может поменять смысл без изменений в твоём git
   ([Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)).
   Flux про remote bases: `--no-remote-bases=true` рекомендован для герметичности
   ([Flux Security Best Practices](https://fluxcd.io/flux/security/best-practices/)).
3. **`kustomize helmCharts` как основной механизм чартов.** Kustomize сам
   ограничивает фичу «limited subset», без private repo auth
   ([Kustomize helmCharts](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/helmcharts/)).
4. **ApplicationSet с шаблонным `project` из неконтролируемого git-источника.**
   Явное предупреждение вендора о privilege escalation
   ([ApplicationSet Security](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Security/)).
5. **Жадный git file generator** — предупреждение в доках
   ([Git File Generator Globbing](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Git-File-Globbing/)).
6. **Plaintext-секреты в git-источнике Flux** — проверяется аудитом
   ([Flux Security Best Practices](https://fluxcd.io/flux/security/best-practices/)).
7. **`block` в Helm вместо `include`** — непредсказуемый override
   ([Helm: Avoid Using Blocks](https://helm.sh/docs/chart_template_guide/subcharts_and_globals/)).

Отмечено как практика сообщества/вывод (не вендорская формулировка): держать в
репо полную копию `values.yaml` апстрима; один гигантский Kustomization на все
приложения; смешивать среды namespace'ами в общем кластере (у нас это прямо
запрещено ADR 0001).

---

## Не подтверждённые утверждения

Проверено по первоисточникам: канонические раскладки Flux (monorepo / per-env /
per-team / per-app) и примеры `flux2-kustomize-helm-example`,
`flux2-multi-tenancy`; ApplicationSet git-генераторы и их ограничения;
Argo Best Practices и Cluster Bootstrapping; sync-waves и hooks; resource
tracking; Flux `Kustomization` (`path`, `dependsOn`, `wait`, `healthChecks`,
`targetNamespace`, `suspend`); `HelmRelease` (`chart.spec` vs `chartRef`,
`valuesFrom`, `dependsOn`, `driftDetection`, `disableTakeOwnership`);
источники `HelmRepository`/`OCIRepository`/`GitRepository`; Kustomize
`helmCharts`; Helm subcharts/globals и library charts; Flux security best
practices; OpenGitOps principles. Следующее **не** подтверждено напрямую:

1. **Кросс-вендорного официального гайда «Argo CD → Flux» не найдено.**
   Процедура в разделе 8 — синтез из подтверждённых механизмов (orphan-удаление
   Argo, `suspend` и takeover во Flux), а не цитата. Перед выполнением проверять
   на тестовом приложении.
2. **«У Flux нет wildcard в `spec.path`»** — следует из описания поля (один
   каталог) и API, но отдельной фразы «wildcards не поддерживаются» в доке нет.
3. **«ApplicationSet git-генератор плохо масштабируется»** — первоисточник
   говорит о жадности file-генератора и о поллинге (по умолчанию 3 минуты), но
   цифр производительности не даёт. Оценка «плохо для 60 апп» — наша.
4. **«Wrapper/umbrella chart — антипаттерн»** — вендоры так не формулируют;
   Argo даже приводит `helm-dependency` как поддерживаемый пример. Тезис
   сформулирован как «нужен только под добавление шаблонов».
5. **`Kustomization.spec.postBuild.substitute` в применении к values
   `HelmRelease`** — фича упомянута в TOC и общих доках, но детально не
   проверялась; перед использованием сверить семантику подстановки.
6. **Оценки ресурсов/скорости Flux vs Argo** в этом документе не даются —
   см. `argo-cd-vs-flux-cd.md` и его оговорки.
7. **Имена чартов/версии для конкретных сервисов** (forgejo-helm, immich-charts
   и т.п.) в эскизах не верифицированы; перед миграцией сверять с апстримом.
8. **Поведение `kubeseal`/SealedSecrets при смене namespace** многократно
   зафиксировано в репозитории (`docs/adr/0001`, `k8s/cnpg/README.md`), но в
   этой сессии по докам bitnami не перепроверялось.

---

## См. также

- [argo-cd-vs-flux-cd.md](./argo-cd-vs-flux-cd.md) — почему целевой инструмент Flux.
- [../config-secrets-templating.md](../config-secrets-templating.md) — принятая
  схема SOPS + age + vals (реестр секретов).
- [../secret-management-providers.md](../secret-management-providers.md) —
  обоснование маршрута секретов.
- `k8s/argocd/README.md` — текущий пробный стенд и правило «не пересекать пути».
- `docs/adr/0001-namespace-ownership.md`, `docs/adr/0002-cnpg-cluster-grouping.md`,
  `docs/adr/0003-cluster-naming-and-major-upgrade.md` — доменные решения, на
  которые опирается раскладка.
- `CONTEXT.md` — словарь («сервис», «платформенный компонент», «среда»).
- `k8s/cnpg/README.md` — боль с порядком «оператор → CR», которую структурно
  закрывает `platform/{controllers,configs}`.

### Источники

Flux:

- [Ways of structuring your repositories](https://fluxcd.io/flux/guides/repository-structure/)
- [Manage Helm Releases](https://fluxcd.io/flux/guides/helmreleases/)
- [Kustomization](https://fluxcd.io/flux/components/kustomize/kustomizations/)
- [OCIRepository](https://fluxcd.io/flux/components/source/ocirepositories/)
- [HelmRelease API (helm-controller)](https://github.com/fluxcd/helm-controller/blob/main/docs/spec/v2/helmreleases.md)
- [Sealed Secrets](https://fluxcd.io/flux/guides/sealed-secrets/)
- [Security Best Practices](https://fluxcd.io/flux/security/best-practices/)
- [fluxcd/flux2-kustomize-helm-example](https://github.com/fluxcd/flux2-kustomize-helm-example)
- [fluxcd/flux2-multi-tenancy](https://github.com/fluxcd/flux2-multi-tenancy)

Argo CD:

- [Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [Cluster Bootstrapping](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [Introduction to ApplicationSet](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/)
- [ApplicationSet Git Generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Git/)
- [ApplicationSet Security](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Security/)
- [Sync Phases and Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [Resource Tracking](https://argo-cd.readthedocs.io/en/stable/user-guide/resource_tracking/)
- [argoproj/argocd-example-apps](https://github.com/argoproj/argocd-example-apps)

Kubernetes / Helm / GitOps:

- [Kustomize `helmCharts`](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/helmcharts/)
- [Helm: Subcharts and Global Values](https://helm.sh/docs/chart_template_guide/subcharts_and_globals/)
- [Helm: Library Charts](https://helm.sh/docs/topics/library_charts/)
- [OpenGitOps principles](https://github.com/open-gitops/documents/blob/main/PRINCIPLES.md)
