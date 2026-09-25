# Порядок полей в манифестах Kubernetes: форматтеры, сортировки и поддержка CRD

Дата исследования: 2026-09-25. Данные GitHub API и локальные прогоны — на эту дату.
Актуальная ветка Kubernetes на момент исследования: v1.37, kustomize v5.8.1, kpt v1.0.1.

Смежные исследования: [linting-tools-comparison.md](./linting-tools-comparison.md) — валидация и
best practices (другой класс инструментов, пересечений по функциям почти нет),
[gitops-repo-structure.md](./gitops-repo-structure.md) — структура репозитория и порядок применения.

> Терминологическое предупреждение. «Линтер» (читает и сообщает) и «форматтер» (переписывает файл)
> — разные классы инструментов. Сортировка полей — работа форматтера в режиме `--fix`.
> В [linting-tools-comparison.md](./linting-tools-comparison.md) перечислены 12 линтеров, и **ни один
> из них не переставляет поля**. Это ключевой факт исследования: искать сортировку полей среди линтеров
> бессмысленно, и это же объясняет, почему результат гуглится плохо.

---

## Короткий вывод

1. **Готового поддерживаемого CLI-форматтера с сортировкой полей не существует.** Механизм есть
   (это код `kyaml`), но обе его CLI-обёртки (`kustomize cfg fmt`, `kpt cfg fmt`) удалены в 2022–2023.
2. **Движок — `kyaml` из kustomize.** Реализация: `kyaml/yaml/order.go` (словарь приоритетов) +
   `kyaml/kio/filters/fmtr.go` (алгоритм). Логика: известные поля в порядке таблицы, неизвестные —
   лексикографически после.
3. **«Поддержка CRD» здесь бесплатна и не является фичей.** Сортировка вообще не использует схему.
   Схема подключается отдельно и влияет только на квотинг скаляров, но не на порядок.
4. **Единственный работающий способ сегодня** — KRM-функция `ghcr.io/kptdev/krm-functions-catalog/format`.
   Код архивирован в каталоге, но образ живой, multi-arch.
5. **Задача признана и брошена официально.** `kpt#2637` «Provide a way to order fields according to
   openapi schema» открыт с 2022-01-06, 0 комментариев. Это буквально наша задача.
6. **Словарь приоритетов устарел.** `order.go` не менялся с 2020-12-15. Свою реализацию придётся
   писать на базе этого списка, а не копировать его один в один.

---

## 1. Что значит «порядок полей в логическом порядке»

Целевой вид — как манифест пишет человек, знающий API:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  template:
    spec:
      containers:
      - name: app
        image: nginx:1.27
```

Поля группируются по смыслу: идентификация → желаемое состояние → шаблон → конкретный объект →
его настройки. Это противоположно и алфавиту, и порядку «как вернул API-сервер».

### Три разных порядка, которые нельзя путать

| Порядок | Что это | Кто задаёт |
|---|---|---|
| **Порядок полей внутри объекта** | `name, image, env, ports` внутри `containers[0]` | Тема этого документа |
| **Порядок объектов (документов)** | как `kustomize build` раскладывает CR по apply-порядку | `kustomize sortOptions.order: legacy` |
| **Порядок объектов в файле** | в каком порядке лежат документы в `.yaml` | вручную / `kustomize sortOptions` |

Смешение этих трёх — источник почти всех путаниц в этой теме, включая мою первую
(неверную) формулировку «kustomize сортирует поля».

---

## 2. Движок: kyaml

Модуль `sigs.k8s.io/kustomize/kyaml`, репозиторий
[kubernetes-sigs/kustomize](https://github.com/kubernetes-sigs/kustomize), подкаталог `kyaml/`.

### 2.1 Словарь приоритетов

[`kyaml/yaml/order.go`](https://github.com/kubernetes-sigs/kustomize/blob/master/kyaml/yaml/order.go) —
список `fieldSortOrder` (~120 имён), сгруппированный по смыслу, плюс `FieldOrder` (индекс в map).
Структура списка:

```
// top-level metadata
name, generateName, namespace, clusterName, apiVersion, kind, metadata, type, labels, annotations,
spec, status,
// secret and configmap
stringData, data, binaryData,
// cronjobspec, daemonsetspec, deploymentspec, statefulsetspec, jobspec
parallelism, completions, activeDeadlineSeconds, backoffLimit, replicas, selector, manualSelector,
template, ttlSecondsAfterFinished, volumeClaimTemplates, service, serviceName, podManagementPolicy,
updateStrategy, strategy, minReadySeconds, revision, revisionHistoryLimit, paused,
progressDeadlineSeconds,
// podspec scalars → podspec lists/maps → podspec objects
initContainers, containers, volumes, securityContext, imagePullSecrets, affinity, tolerations, ...
// containers
image, command, args, workingDir, ports, envFrom, env, resources, volumeMounts, volumeDevices,
livenessProbe, readinessProbe, lifecycle, terminationMessagePath, terminationMessagePolicy,
imagePullPolicy, securityContext, stdin, stdinOnce, tty,
// service, ports, volumemount, envvar + envvarsource
```

### 2.2 Алгоритм

[`kyaml/kio/filters/fmtr.go`](https://github.com/kubernetes-sigs/kustomize/blob/master/kyaml/kio/filters/fmtr.go),
`func (s sortedMapContents) Less`:

```go
iOrder, foundI := yaml.FieldOrder[iFieldName]
jOrder, foundJ := yaml.FieldOrder[jFieldName]
if foundI && foundJ {
	return iOrder < jOrder
}
if foundI {
	return true   // известные поля раньше неизвестных
}
if foundJ {
	return false
}
// оба неизвестны — лексикографически
return iFieldName < jFieldName
```

Док-комментарий в начале файла (`fmtr.go:9`) — формальный ответ на вопрос про CRD:

> All Resources, including non-builtin Resources such as CRDs, share the same field precedence.
> Fields that do not appear in the explicit ordering are ordered lexicographically.

### 2.3 Про CRD: почему это работает без схемы

Флаг `FormatFilter.UseSchema` (в `format`-функции и в kpt включён) подключает
`openapi.SchemaForResourceType()`. По коду `fmtNode` он используется ровно в одном месте:

```go
if n.Kind == yaml.ScalarNode && schema != nil && schema.Schema != nil {
	// ensure values that are interpreted as non-string values (e.g. "true") are properly quoted
	yaml.FormatNonStringStyle(n, *schema.Schema)
}
```

То есть схема влияет **только** на квотинг (`bar: 100` → `bar: "100"`), и **никак** — на порядок.
`openapi.SchemaForResourceType` в kyaml знает лишь встроенные типы Kubernetes; для CRD вернёт `nil`.

**Отсюда важное следствие для проектирования.** «Логический порядок» для CRD в природе не
существует: порядок `properties` в OpenAPI-схеме CRD — это порядок полей в Go-структуре
контроллера, произвольный с точки зрения читателя манифеста. Единственная достижимая
детерминированная схема — общий прецедент верхнего уровня + алфавит внутри `spec`. Ни один
существующий инструмент не делает лучше, и ни один не сможет без собственного словаря.

### 2.4 Что ещё умеет движок

- **Сортировка списков** — только для двух путей и только для whitelist видов
  (`order.go`: `WhitelistedListSortKinds`, `WhitelistedListSortApis`, `WhitelistedListSortFields`):
  - `.spec.template.spec.containers` → по `name`
  - `.webhooks.rules.operations` → по значению

  Списки внутри CRD не сортируются вообще.
- **Нормализация отступов и стиля** (компактный отступ для sequence, 2 пробела).
- **Квотинг неоднозначных скаляров** — по схеме, для CRD без схемы.
- **Оптимайт-аннотация** `config.kubernetes.io/formatting: none` — объект не форматируется.
  Значения: `standard` (по умолчанию) и `none`.

### 2.5 Ограничения, о которых надо знать до реализации

1. **`order.go` не менялся с 2020-12-15** (последний коммит — механический
   `update kyaml api version`). Список заморожен примерно на Kubernetes 1.20. В нём нет
   `seccompProfile`, `os`, `hostUsers`, `appArmorProfile`, `podReplacementPolicy`.
   Новые поля уедут в хвост и станут алфавитными — то есть откатится к худшему варианту.
2. **Сортировка по имени поля, а не по пути.** `securityContext` у контейнера и у пода делят один
   приоритет; `activeDeadlineSeconds` в JobSpec и в PodSpec — один элемент списка. Для известных
   типов это работает, потому что список составлялся вручную именно под эти структуры.
3. **Коллизии с CRD неизбежны.** Любой CRD с полем `name`, `spec`, `status`, `template`, `data`
   получит «встроенный» приоритет. Для `spec.<что-то>` это безвредно, но если у CRD есть поле
   `strategy` или `replicas` на верхнем уровне, оно встанет в середину — выглядит странно, но не ломается.
4. **Нет версионности словаря.** Формат не несёт в себе номер Kubernetes-версии, к которой
   привязан порядок. Своя реализация должна это добавить.

---

## 3. Карта всех известных утилит

Колонка «сортирует поля» — главный критерий. Проверено по исходникам и/или запуском.

### 3.1 Форматтеры и сортировщики

| Утилита | Репозиторий | Сортирует поля | Чем задаётся порядок | CRD | Пишет в файл | Статус |
|---|---|---|---|---|---|---|
| **`kustomize build`** | [kubernetes-sigs/kustomize](https://github.com/kubernetes-sigs/kustomize) | ⚠️ **да, но алфавитом** | нет, побочный эффект | ✅ так же | ✅ | жив, v5.8.1 |
| `kustomize sortOptions` | там же | ❌ только документы | `defaultOrderFirst/Last` | ✅ | ✅ | жив, с v5.0.0 |
| `kustomize cfg fmt` | там же | ✅ идеально | `fieldSortOrder` | ✅ | ✅ | ❌ **удалён 2022-12-14** |
| `kpt cfg fmt` | [kptdev/kpt](https://github.com/kptdev/kpt) | ✅ | `fieldSortOrder` | ✅ | ✅ | ❌ **удалён в v1** |
| KRM-функция `format` | [kptdev/krm-functions-catalog](https://github.com/kptdev/krm-functions-catalog/tree/main/archived/functions/go/format) | ✅ | `fieldSortOrder` | ✅ | ✅ | ⚠️ архивирован, образ жив |
| `kyaml` (как библиотека) | kubernetes-sigs/kustomize | ✅ | `fieldSortOrder` | ✅ | ✅ | ✅ живой модуль |
| **`kubefmt`** | [golang-cz/kubefmt](https://github.com/golang-cz/kubefmt) | ✅ **намеренно алфавитом** | алфавит, без конфига | ✅ (как алфавит) | ✅ | ⚠️ 0★, пуш 2025-02-25 |
| `kfmt` | [dippynark/kfmt](https://github.com/dippynark/kfmt) | ❌ раскладывает по каталогам | — | — | ✅ | ⚠️ 16★, пуш 2024-12-21 |
| `yamlfmt` | [google/yamlfmt](https://github.com/google/yamlfmt) | ❌ **вообще не сортирует** | — | — | ✅ | ✅ жив |
| `yq sort_keys(..)` | [mikefarah/yq](https://github.com/mikefarah/yq) | ✅ алфавитом | алфавит / `sort_by(..)` | ✅ | ✅ (`-i`) | ✅ жив |
| `jsonnetfmt` | [google/jsonnet](https://github.com/google/jsonnet) | ❌ только `--sort-imports` | — | — | ✅ | ✅ жив |
| `slim fmt --kubernetes` | `slim-ai/slim` | ✅ | собственный словарь | ✅ | ✅ | ❌ **репозиторий 404** |
| `KubeTidy` | [KubeDeckio/KubeTidy](https://github.com/KubeDeckio/KubeTidy) | ❌ чистит kubeconfig | — | — | ✅ | ⚠️ 46★ |

### 3.2 Линтеры (сортировки полей нет ни у одного)

Проверено: [kube-linter](https://github.com/stackrox/kube-linter) (флаг `--format` — это формат
отчёта: json/sarif/checkstyle/codeclimate/plaintext, а не перезапись файлов),
[kubeconform](https://github.com/yannh/kubeconform), [polaris](https://github.com/FairwindsOps/polaris)
(умеет auto-fix через mutating webhook, но по правилам политик, а не по порядку полей),
checkov, trivy, kube-score, kubescape, kube-bench, datree (archived).

Общие YAML-форматтеры, которые иногда подставляют вместо k8s-форматтера — и которые **тоже не
сортируют поля**: `yamllint` (только style/lint), `prettier` (+ плагины), `rufo`.

### 3.3 Не варианты (найдены, отброшены)

| Репозиторий | ★ | Почему отброшен |
|---|---|---|
| [metawave/k8s-yaml-fmt](https://github.com/metawave/k8s-yaml-fmt) | 0 | «enforces idiomatic key ordering», но 0★, нет активности |
| [JoshVanL/kube-yaml-sort](https://github.com/JoshVanL/kube-yaml-sort) | 3 | самопаль, алфавит |
| [xrstf/kubesort](https://github.com/xrstf/kubesort) | 0 | сортировка документов, не полей |
| [60k41p/k8s-manifest-sorter](https://github.com/60k41p/k8s-manifest-sorter) | 0 | сортировка документов |
| [amaanx86/kfix](https://github.com/amaanx86/kfix) | 0 | «opinionated», но без экосистемы |
| [phanimarupaka/kustomize2](https://github.com/phanimarupaka/kustomize2) | 0 | форк kustomize с живым `cfg fmt`, но пуш 2021-02-21, заброшен |

### 3.4 Ловушки при поиске (проверено лично)

- **`yamlfmt` имеет форматтер `formatters/kyaml`** — но это **не** kyaml из kustomize. Это формат
  KYAML из `sigs.k8s.io/yaml/kyaml` (всегда кавычки, `{}`/`[]`). Импортируется как
  `sigs.k8s.io/yaml/kyaml`, не `sigs.k8s.io/kustomize/kyaml`. Ключи не сортирует.
- **`kubefmt` от Votruba делает обратное.** Это не дилетантская поделка, а сознательная позиция:
  сортировка ключей алфавитом ради детерминированных диффов. Целое направление в PHP/Doctrine-мире
  на этом («ordered by keys»). Наша задача противоположна по существу, поэтому имя `kubefmt` и
  его философию надо обходить.
- **KRM-каталог `kpt` до сих пор в README `format`-функции обещает «Field ordering follows the
  ordering defined in the OpenAPI document»** — формулировка неточная, никакой OpenAPI-документ
  не используется, порядок зашит в Go-литерал. Не опираться на неё при проектировании.

---

## 4. Эмпирическая проверка

### 4.1 `kustomize build` алфавитит всё дерево

kustomize v5.8.1, darwin/arm64. На вход — намеренно перетасованные Deployment, ConfigMap, CRD и
кастомный ресурс (`example.com/v1 MyCRD`). На выходе:

```yaml
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  strategy:
    type: RollingUpdate
  template:
    spec:
      containers:
      - env:
        - name: LOG
          value: debug
        image: nginx:1.27
        imagePullPolicy: IfNotPresent
        name: app
        ports:
        - containerPort: 8080
        resources:
          limits:
            cpu: 100m
      restartPolicy: Always
```

Порядок внутри контейнера стал `env, image, imagePullPolicy, name, ports, resources`, а
`restartPolicy` уехал вниз, после `containers`. Верхний уровень выглядит осмысленно
(`apiVersion, kind, metadata, spec, status`) — но это **совпадение с алфавитом**, а не работа схемы.

Механизм: `resWrangler.AsYaml()` (`api/resmap/reswrangler.go:285`) → `Resource.AsYAML()`
(`api/resource/resource.go:382`) → `RNode.MarshalJSON()` (`kyaml/yaml/rnode.go:975`) →
`Unmarshal` в `map[string]interface{}` → `json.Marshal`, а Go сортирует ключи map по алфавиту.

CRD и кастомный ресурс обрабатываются ровно так же, то есть `kustomize build` **гарантированно**
приводит любой CRD к алфавиту. Побочно он же сортирует документы в apply-порядок
(`Namespace, ResourceQuota, StorageClass, CRD, ServiceAccount, Role, ClusterRole, RoleBinding,
ClusterRoleBinding, ConfigMap, Secret, Endpoints, Service, LimitRange, PriorityClass, PV, PVC,
Deployment, StatefulSet, CronJob, PDB, ... MutatingWebhookConfiguration, ValidatingWebhookConfiguration`),
неизвестные виды уходят в середину/хвост по строке `group_version_kind`.

### 4.2 Порядок от API-сервера (требует проверки на кластере)

Прослежено по коду, **живым кластером не подтверждено** (на момент исследования нет kubeconfig):

- Для встроенных типов ответ API-сервера сохраняет порядок полей Go-структуры.
- Для CR объект — это `unstructured.Unstructured` (`apiextensions-apiserver`,
  `pkg/registry/customresource/etcd.go`), сериализация идёт через `json.Marshal` по `map`,
  что сортирует ключи по алфавиту на всех уровнях.

Практическое следствие, если подтвердится: `kubectl get <cr> -o yaml > back.yaml` для кастомного
ресурса — это гарантированная потеря ручного порядка полей. Оформить отдельным тикетом с
проверкой на нашем кластере.

---

## 5. Почему это убрали — три отдельные истории

Ни в одной из историй формат не признали ненужным по существу. Везде это побочный эффект
scope-решения, и opt-in замена так и не была построена.

### 5.1 kustomize: «это не про kustomize»

[kustomize#3953](https://github.com/kubernetes-sigs/kustomize/issues/3953) «Deprecation of
`kustomize cfg` and `kustomize fn` alpha commands» (KnVerey, 2021-06-02). Ключевая формулировка:

> They're loosely related to Kustomize in that keeping your configuration expressed in the
> canonical APIs enables you to use such tools on your raw config. But at the same time,
> **these tools aren't specific to Kustomize or part of recommended Kustomize workflows AFAIK.**

Причины:
1. **Стабилизация API.** Всё было `[Alpha]` и блокировало путь к Kustomization v1 API.
2. **Форматтер вне scope.** Аргумент про `fmt` дословно: «to format kustomize output, you should
   probably declare a transformer in your Kustomization» — переучить пользователя вместо
   того, чтобы дать инструмент.
3. **Дублирование с kpt.** По setter'ам: «aren't setters more of a kpt concept?» По форматтеру
   прямого возражения не было — попал под общий разряд «мутирующие команды».

Хронология:

| Дата | Событие |
|---|---|
| 2021-06-02 | Открыт #3953 с предложением удалить 10 из 14 команд `cfg` |
| 2021-07-07 | [#4021](https://github.com/kubernetes-sigs/kustomize/pull/4021) «Retain field order after running any arbitrary functions» — kustomize переходит на **сохранение** пользовательского порядка |
| 2021-07-19 | `16dcc98c` — коммит «deprecate some cfg commands» (#4048) |
| 2022-12-07 | Открыт #4915 на удаление |
| 2022-12-14 | [#4930](https://github.com/kubernetes-sigs/kustomize/pull/4930) merged — удаление |
| 2023-01 | `kustomize v5.0.0` release notes: `cfg fmt` в breaking changes **без указания замены** |

Ловушка при навигации по репозиторию kustomize: файл
[cmd/config/docs/commands/fmt.md](https://github.com/kubernetes-sigs/kustomize/blob/master/cmd/config/docs/commands/fmt.md)
**до сих пор лежит в `master` и описывает `kustomize cfg fmt` как рабочую команду** с примерами
вызова. Deprecation добавляли в Go-код (`Short`-описания команд), а не в этот `.md`, и при удалении
команды документацию не почистили. Команды `cfg` в бинаре после v5.0.0 — только `cat`, `count`,
`grep`, `tree` (проверено на v5.8.1). Не проектировать, доверившись репозиторию.

Альтернативу «вынести в отдельный бинарник / в cli-experimental» на #3953 обсуждали, но не
реализовали. В том же релизе v5.0.0 добавили `sortOptions` (#4019) — но он сортирует
**документы**, а не поля, то есть заменой не является. Документ
[Eschewed Features](https://github.com/kubernetes-sigs/kustomize/blob/master/site/content/en/contribute/features/eschewedfeatures.md)
про порядок полей не упоминает вообще: позиция «мы за/против форматирования» в kustomize
никогда не была сформулирована.

Была и реальная техническая причина не переиспользовать kyaml внутри kustomize
([комментарий natasha41575, 2021-07-16](https://github.com/kubernetes-sigs/kustomize/issues/3953)):
kustomize теряет комментарии на входе, из-за чего `kpt-set: ${nginx-replicas}`-аннотации
уничтожались до запуска KRM-функции. Ответ KnVerey: «it sounds like we must not be using kyaml at
our entry point… I suspect it won't be smooth sailing. E.g. if that effectively changes us over to
a yaml 1.2 unmarshaler, booleans will get treated differently».

### 5.2 kpt: объявлен избыточным из-за соседнего фикса

[kpt#2108](https://github.com/kptdev/kpt/issues/2108) «Epic: Consistent Formatting»
(phanimarupaka, 2021-05-26 → закрыт 2026-07-08).

**Phase 1 (для beta.2, 2021-07) — выполнено:**
- Preserve field ordering (это `kustomize#4021` от 2021-07-07)
- Preserve sequence node indentation
- **Disable formatting for eval and render commands**

Phase 1 чинил реальные жалобы: [#2104](https://github.com/kptdev/kpt/issues/2104),
[#2101](https://github.com/kptdev/kpt/issues/2101), [#2332](https://github.com/kptdev/kpt/issues/2332),
[#2342](https://github.com/kptdev/kpt/issues/2342), [#2068](https://github.com/kptdev/kpt/issues/2068) —
люди жаловались, что `kpt fn render` переставляет поля. Решение: перестать сортировать.

Через 19 дней — [krm-functions-catalog#495](https://github.com/kptdev/krm-functions-catalog/pull/495)
«Deprecate Format docs» добавляет в README форматтера:

> This function works well with 1.0.0-beta.1 or lower versions of kpt. Starting from
> 1.0.0-beta.2, **the order of the fields is preserved by kpt CLI.**

Здесь происходит подмена понятий: «kpt больше не переставляет мои поля» ≠ «мне не нужно, чтобы
поля стояли в каноническом порядке». Первое — про дефолт, второе — про запрос по явному желанию.

**Phase 2 (long term) — не выполнено:**
- [ ] Design proposal when and how to format resources → [#2349](https://github.com/kptdev/kpt/issues/2349)
      (открыт 2021-06-29, 0 комментариев)
- [ ] Implement the items in approved proposal

**[kpt#2637](https://github.com/kptdev/kpt/issues/2637) «Provide a way to order fields according to
openapi schema» — открыт с 2022-01-06, 0 комментариев.** Тело issue:

> Currently format function is deprecated in kpt and the field order preservation logic makes it
> unusable. We need to figure out a way where users can order fields based on openapi schema order,
> basically the older functionality **when explicitly specified by the user**.

Это буквально наша задача, оформленная как признанный пробел экосистемы, и её никто не
подхватил за четыре года. Эпик `#2108` закрыли 2026-07-08 комментарием
«Most of this work was still done.» — при том что оба Phase 2 чекбокса остались незакрытыми.

Отдельно: в kpt **остался неиспользуемый код** — `FormatPackage(pkgPath)` в
`pkg/lib/pkg/util.go:361` вызывает ровно `filters.FormatFilter{UseSchema: true}`, но вызывающих
сторон в kpt v1.0.1 не нашлось. То есть переиспользовать движок проще, чем кажется.

### 5.3 KRM-каталог: задело волной

`format` переехал в `archived/` коммитом 2025-11-05, PR
[#1201](https://github.com/kptdev/krm-functions-catalog/pull/1201) «Archive unsupported fns».
Тело PR:

> Archive unsupported KRM functions: **GoogleCloud Platform specific functions. TypeScript functions.**

Format — Go-функция, в списке PR её нет. Она **задела волной** при чистке GCP/TypeScript-функций,
и в `metadata.yaml` до сих пор стоит `hidden: true`. Решения «форматтер не нужен» не принимал
никто — это зачистка, а не решение по существу.

**Состояние на 2026-09-25:** образ `ghcr.io/kptdev/krm-functions-catalog/format` доступен
(теги `latest` + 30 тегов-коммитов, платформы linux/amd64 и linux/arm64, манифест проверен через
ghcr API). Код в `archived/`, в `kpt fn catalog` не находится, CI у образа нет, `main.go`
поддерживает `command.StandaloneEnabled`, то есть бинарь рассчитан и на standalone-запуск.
**Фактический запуск не проверен** — Docker-демон на машине исследования не был запущен.

---

## 6. Ландшафт имён

Проверено на GitHub (`repositories` search), npm registry и Homebrew formulae.

| Имя | Занято? | Чем |
|---|---|---|
| `kubefmt` | да | `golang-cz/kubefmt` — форматтер, **сортирует алфавитом** |
| `kfmt` | да | `dippynark/kfmt` (16★), раскладка манифестов по каталогам |
| `kubetidy` | да | `KubeDeckio/KubeTidy` (46★), чистка kubeconfig; + ещё 1 репо |
| `k8sfmt` | частично | `ggilmore/k8sfmt`, 0★ |
| `kubiform` | **свободно** | — |
| `kubocanon` | **свободно** | — |
| `kubosort` | **свободно** | — |
| `kubeorder` | **свободно** | — |
| `kuboshape` | **свободно** | — |
| `kubeprettify` | **свободно** | но претендует на территорию `prettier` с алфавитной философией |

Плюс ловушка: `kind` в этом пространстве занято (kind.sigs.k8s.io), на имена с `kind` в составе
не наступать.

Критерии выбора, которые стоит зафиксировать до реализации:
1. Суффикс `-fmt` — жанровый маркер в Go-инструментарии (`gofmt`, `goimports`, `rustfmt`).
   Человек, увидевший имя в выводе CI, сразу понимает: это форматтер, файлы перезаписаны.
   Имя отличается от `kubefmt`, поэтому путаницы с алфавитной школой не будет.
2. Имя не должно обещать «сортировку ресурсов» — этим уже занят `kustomize sortOptions`.
3. Имя должно пережить расширение области (сортировка документов, обёртка строк и т.п.).

Интерфейс, который напрашивается (по аналогии с `gofmt`, а не с subcommand-овским):

```bash
kubiform ./apps          # перезаписать (как gofmt без флагов)
kubiform -l ./apps      # вывести имена изменённых, не трогая (как gofmt -l)
kubiform -d ./apps      # diff вместо записи
kubiform -check ./apps   # режим CI: ненулевой код возврата при расхождениях
```

Плюс совместимость с KRM: уважать `config.kubernetes.io/formatting: none` (механизм готов).

---

## 7. Варианты реализации

| Вариант | Что это | Плюсы | Минусы |
|---|---|---|---|
| **A. KRM-функция `format`** | `docker run --rm -i ghcr.io/kptdev/krm-functions-catalog/format` | ноль кода, движок ровно тот | чужой архивный образ без CI, стейл-широт, нужен Docker в pre-commit |
| **B. Свой tool на kyaml** | `filters.FormatInput(io.Reader)` / `filters.FormatFilter` (~40 строк) | контроль, свой словарь, ноль внешних образов | надо писать и поддерживать |
| **C. Не сортировать** | полагаться на `yamllint` | ноль работы | отсутствие единого канона |

По инфраструктуре репозитория: `kustomize`, `kpt`, `yq` не установлены; `kubeconform` и
`kube-linter` есть. Go в репозитории уже используется (`packages/cert-manager-webhook-dns01/go.mod`),
поэтому естественное место для варианта B — `packages/kubiform/`.

**Следствие для дизайна B:** начинать с копирования `order.go` нельзя — список устарел на
несколько лет Kubernetes. Свой словарь приоритетов писать с нуля, покрывая актуальные
`PodSpec`/`Container`/`Deployment`/`Service`/`Ingress`/`Volume`-поля, и явно версионировать его
привязку к Kubernetes-версии. Плюс решить, наследуем ли мы поведение
`config.kubernetes.io/formatting: none` ради совместимости с KRM-конвейерами.

Идемпотентность (запуск дважды не даёт diff) — обязательный тест, а не опция: у `kyaml`-движка
она завязана на `MatchFilesGlob`, `PreserveSeqIndent`, `WrapBareSeqNode` и очистку
reader-аннотаций (`kioutil.IndexAnnotation`, `SeqIndentAnnotation`), которые надо аккуратно
воспроизвести.

---

## 8. Открытые вопросы

1. **Порядок полей CR от API-сервера** — проверить на нашем кластере
   (`kubectl get <cr> -o yaml` для ресурса, чьи поля в манифесте записаны не по алфавиту).
2. **Реальный запуск `format`-образа** — поднять Docker-демон, прогнать на тестовом наборе,
   сверить вывод с ожидаемым каноническим порядком.
3. **Порядок полей в `values.yaml` и в шаблонах Helm** — вынесен ли он в ту же задачу.
   В `.kube-linter.yaml` эти пути уже исключены из линтинга, логично исключать их и из
   форматирования.
4. **Поведение при анкорах и алиасах.** Известный грабли: сортировка ключей ломает YAML merge-anchors,
   потому что `<<: *base` не является обычным ключом. Требует решения: рефлейсить, выносить
   `<<` в конец, или отказываться от сортировки объекта с анкорами.
5. **Аннотация opt-out** — наследовать ли `config.kubernetes.io/formatting: none` (совместимость
   с KRM) или ввести свою.
6. **Стратегия первого прогона.** Канонизация даёт один большой diff на каждый файл. Нужен
   отдельный тикет-миграция с понятной границей (например, только `platform/` и `apps/`,
   не трогая `platform/homelab/templates/**`).

---

## Источники

Первоисточники, а не пересказы. Все даты и статусы — на 2026-09-25.

**Движок**
- [kyaml/yaml/order.go](https://github.com/kubernetes-sigs/kustomize/blob/master/kyaml/yaml/order.go) — словарь приоритетов, whitelist списков
- [kyaml/kio/filters/fmtr.go](https://github.com/kubernetes-sigs/kustomize/blob/master/kyaml/kio/filters/fmtr.go) — алгоритм, `UseSchema`, аннотация `config.kubernetes.io/formatting`
- [kyaml/yaml/rnode.go#L975](https://github.com/kubernetes-sigs/kustomize/blob/master/kyaml/yaml/rnode.go) — `MarshalJSON`, источник алфавитного порядка
- [api/resource/resource.go#L382](https://github.com/kubernetes-sigs/kustomize/blob/master/api/resource/resource.go) — `AsYAML`
- [api/resmap/reswrangler.go#L285](https://github.com/kubernetes-sigs/kustomize/blob/master/api/resmap/reswrangler.go) — `AsYaml` в выводе build
- [plugin/builtin/sortordertransformer/SortOrderTransformer.go](https://github.com/kubernetes-sigs/kustomize/blob/master/plugin/builtin/sortordertransformer/SortOrderTransformer.go) — `defaultOrderFirst`/`defaultOrderLast`, ссылка на [#3913](https://github.com/kubernetes-sigs/kustomize/issues/3913)
- [cmd/config/docs/commands/fmt.md](https://github.com/kubernetes-sigs/kustomize/blob/master/cmd/config/docs/commands/fmt.md) — документация удалённой команды, осталась в репозитории

**Удаление в kustomize**
- [kustomize#3953](https://github.com/kubernetes-sigs/kustomize/issues/3953) — исходный тред депрекейта (причины, цитаты KnVerey, natasha41575, bgrant0607, marshall007)
- [kustomize#4021](https://github.com/kubernetes-sigs/kustomize/pull/4021) — «Retain field order after running any arbitrary functions»
- [kustomize#4915](https://github.com/kubernetes-sigs/kustomize/issues/4915) — тикет на удаление
- [kustomize#4930](https://github.com/kubernetes-sigs/kustomize/pull/4930) — PR удаления, merged 2022-12-14
- [kustomize v5.0.0 release notes](https://github.com/kubernetes-sigs/kustomize/releases/tag/kustomize%2Fv5.0.0) — breaking changes
- [Eschewed Features](https://github.com/kubernetes-sigs/kustomize/blob/master/site/content/en/contribute/features/eschewedfeatures.md)

**Удаление в kpt и архивирование функции**
- [kpt#2108](https://github.com/kptdev/kpt/issues/2108) — Epic: Consistent Formatting
- [kpt#2349](https://github.com/kptdev/kpt/issues/2349) — design proposal, открыт
- [kpt#2637](https://github.com/kptdev/kpt/issues/2637) — «Provide a way to order fields according to openapi schema», открыт
- [kpt pkg/lib/pkg/util.go#L361](https://github.com/kptdev/kpt/blob/main/pkg/lib/pkg/util.go) — `FormatPackage`, неиспользуемый вызов `FormatFilter`
- [krm-functions-catalog#495](https://github.com/kptdev/krm-functions-catalog/pull/495) — депрекейт docs форматтера
- [krm-functions-catalog#1201](https://github.com/kptdev/krm-functions-catalog/pull/1201) — архивирование, 2025-11-05
- [archived/functions/go/format](https://github.com/kptdev/krm-functions-catalog/tree/main/archived/functions/go/format) — код, `main.go`, `metadata.yaml` (`hidden: true`)
- Образ `ghcr.io/kptdev/krm-functions-catalog/format` — манифест проверен через ghcr API 2026-09-25

**Альтернативы**
- [golang-cz/kubefmt](https://github.com/golang-cz/kubefmt) — «Sorts keys alphabetically»
- [dippynark/kfmt](https://github.com/dippynark/kfmt) — раскладка по каталогам
- [google/yamlfmt](https://github.com/google/yamlfmt) — [formatters/kyaml/formatter.go](https://github.com/google/yamlfmt/blob/main/formatters/kyaml/formatter.go) импортирует `sigs.k8s.io/yaml/kyaml`
- [mikefarah/yq sort_keys](https://github.com/mikefarah/yq/blob/master/pkg/yqlib/doc/operators/sort-keys.md)
- [google/jsonnet cmd/jsonnetfmt.cpp](https://github.com/google/jsonnet/blob/master/cmd/jsonnetfmt.cpp) — только `--sort-imports`
- [datreeio/CRDs-catalog](https://github.com/datreeio/CRDs-catalog) — JSON-схемы популярных CRD (для валидации, не для порядка)
