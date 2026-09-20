# Метрики «по-кубернетовски»: операторы, CRD и готовые дашборды для k0s

Дата исследования: 2026-09-18. Версии сверены с Helm-индексами репозиториев,
GitHub Releases API и исходниками чартов/CRD на дату исследования. Все URL
проверены на доступность. Живых проверок на сервере в рамках этого исследования
не делалось — там, где вывод требует проверки на кластере, это явно помечено.

**См. также:**

- [monitoring-systems-overview.md](../monitoring-systems-overview.md) — сравнение
  продуктов (Prometheus-стек, LGTM, VictoriaMetrics, Zabbix…), аудит уже
  установленного и поэтапный план внедрения. Здесь это **не повторяется**.
- [observability-standards-and-approaches.md](../observability-standards-and-approaches.md)
  — стандарты и протоколы (exposition format, remote write, OTLP, service
  discovery, паттерн ServiceMonitor CRD как концепция).

## Вывод

«Kubernetes way» сбора метрик — это не «правильный scrape.yml», а **оператор +
декларативные CRD**: приложение объявляет intent («у меня есть `/metrics` на
порту X») лейблами и CRD, а контроллер сам генерирует конфиг скрейпера и
перечитывает его без рестарта. Ручной `scrape.yml` из `static_configs` — это ровно
то, что оператор призван заменить.

Для этого homelab рекомендация такая:

1. **Не переходить на kube-prometheus-stack.** Он притащит второй TSDB
   (Prometheus) рядом с уже работающей VictoriaMetrics, второй Grafana,
   node-exporter и kube-state-metrics, то есть на одном узле появятся дубликаты и
   лишний расход RAM/диска. PromQL-совместимость MetricsQL закрывает почти все
   дашборды (см. §3.2 и §3.3).
2. **Взять VictoriaMetrics Operator** (`victoria-metrics-operator` +
   `victoria-metrics-operator-crds`) и переводить текущий стек **инкрементально**:
   `vmagent` Deployment → `VMAgent` CR, статические джобы → `VMStaticScrape` /
   `VMServiceScrape` / `VMPodScrape` / `VMNodeScrape`, правила → `VMRule`.
   Хранилище (`VMSingle`) можно оставить сырым Deployment или позже перевести в
   `VMSingle` CR.
3. **Включить конвертер Prometheus CRD у оператора** (по умолчанию включён) — это
   бесплатный мост: любой сторонний чарт, отдающий `ServiceMonitor`/`PodMonitor`/
   `PrometheusRule`, подхватится без ручной правки. Для этого в кластере должны
   быть CRD `monitoring.coreos.com` (отдельный чарт `prometheus-operator-crds`).
4. **Полный `victoria-metrics-k8s-stack`** — правильный «с нуля», но в этом
   репозитории он сейчас конфликтует с уже развёрнутыми VMSingle/vmagent/Grafana,
   потому что ставит свои. Брать его имеет смысл, если начинать заново или
   осознанно заменить существующее. Полезное из него можно перенести точечно:
   дефолтные `VMRule` (из kube-prometheus) и набор дашбордов.
5. **Grafana** оставить как есть (Deployment + provisioning ConfigMap): это
   минимум движущихся частей на одной ноде. Grafana Operator оправдан, когда
   инстансов много или нужен GitOps-цикл дашбордов как CRD — см. §2.4 и §3.

---

## 1. 🧩 Что такое «Kubernetes way»: оператор и CRD вместо ручного конфига

### 1.1 Операторная модель

[Prometheus Operator](https://prometheus-operator.dev/docs/getting-started/introduction/)
— это Kubernetes-оператор, который «обеспечивает Kubernetes-native развёртывание
и управление Prometheus и связанными компонентами». Он принимает **два класса
CRD** ([design](https://prometheus-operator.dev/docs/getting-started/design/)):

- **Instance-based** — описывают жизненный цикл компонента: `Prometheus`,
  `PrometheusAgent`, `Alertmanager`, `ThanosRuler`. Оператор по каждому объекту
  создаёт `StatefulSet`.
- **Config-based** — описывают, *что* скрейпить и как алертить: `ServiceMonitor`,
  `PodMonitor`, `Probe`, `ScrapeConfig`, `PrometheusRule`, `AlertmanagerConfig`.

Связывание — лейбл-селекторами на instance-объекте:
`serviceMonitorSelector`, `podMonitorSelector`, `probeSelector`,
`scrapeConfigSelector`, `ruleSelector`, плюс парные `*NamespaceSelector`. Правила
стандартных Kubernetes-селекторов: пустой `{}` матчит всё, отсутствующий
(null) — ничего для resource-селекторов либо только свой namespace для
namespace-селекторов.

Механика: оператор рендерит из CRD **итоговый конфиг Prometheus**, кладёт его в
Secret и запускает рядом с Prometheus контейнер-`config-reloader`, который
перечитывает конфиг по изменению — «алерты и recording rules динамически
загружаются без рестарта Prometheus».

### 1.2 CRD-паттерн: что чем заменяет

| CRD | Смысл | Аналог в ручном `scrape.yml` |
|---|---|---|
| `ServiceMonitor` | скрейпить Endpoints/EndpointSlice `Service` по лейблам, по конкретным портам | `static_configs` по k8s-именам + ручной `kubernetes_sd` по сервисам |
| `PodMonitor` | скрейпить поды напрямую (например, порт есть у пода, но не у Service) | `kubernetes_sd_configs: role: pod` + relabel |
| `Probe` | blackbox-пробы (HTTP/TCP/ICMP/DNS) через prober | отдельный job с `blackbox_exporter` |
| `PrometheusRule` | alerting/recording rules | секция `groups` в конфиге Prometheus |
| `ScrapeConfig` | произвольный scrape-конфиг (внешние цели, любой SD) | «сырые» `scrape_configs` |
| `AlertmanagerConfig` | подсекции конфига Alertmanager (routes/receivers/inhibit) | `alertmanager.yml` |

Ключевой сдвиг: **скрейпер не знает про приложения**, пока приложение не
объявило о себе CRD. Новый сервис с `/metrics` = один объект рядом с приложением
(в его namespace, за его GitOps-Application), без правок конфига мониторинга.

### 1.3 Зеркальные CRD VictoriaMetrics

VictoriaMetrics не изобретает свою вселенную, а повторяет паттерн
([operator](https://docs.victoriametrics.com/operator/), полный список —
[API Docs](https://docs.victoriametrics.com/operator/api/), группа
`operator.victoriametrics.com`):

| CRD VictoriaMetrics | Замена в prometheus-operator |
|---|---|
| `VMServiceScrape` | `ServiceMonitor` |
| `VMPodScrape` | `PodMonitor` |
| `VMProbe` | `Probe` |
| `VMRule` | `PrometheusRule` |
| `VMScrapeConfig` | `ScrapeConfig` |
| `VMStaticScrape` | — (статические внешние цели) |
| `VMNodeScrape` | — (kubelet/cAdvisor; в Prometheus-мире это дефолтные ServiceMonitor'ы) |
| `VMAlertmanagerConfig` | `AlertmanagerConfig` |

Instance-based CRD: `VMAgent` (сборщик), `VMAlert` (правила), `VMAlertmanager`
(маршрутизация), `VMSingle`/`VMCluster` (хранилище), `VMAuth` (auth-прокси),
`VMUser`, `VMDistributed`. Есть и CRD для логов/трейсов (`VLSingle`, `VLCluster`,
`VLAgent`, `VTSingle`, `VTCluster`, `VTAgent`), но для вопроса о метриках они не
нужны.

`VMServiceScrape`, как и `ServiceMonitor`, работает по именованному порту
Service'а: `spec.endpoints: [{ port: web }]`, `spec.selector.matchLabels`
([VMServiceScrape](https://docs.victoriametrics.com/operator/resources/vmservicescrape/)).
Дополнительно можно выбрать `discoveryRole: endpoints | service | endpointslice`.
Официально заявлено: «`VMServiceScrape` — это drop-in замена `ServiceMonitor`».

---

## 2. 📦 Операторы и Helm-чарты

### 2.1 Prometheus Operator + kube-prometheus-stack

| | |
|---|---|
| Проект | [prometheus-operator/prometheus-operator](https://github.com/prometheus-operator/prometheus-operator) |
| Версия | [v0.94.0](https://github.com/prometheus-operator/prometheus-operator/releases/tag/v0.94.0) (2026-09-09) |
| Лицензия | Apache-2.0 |
| Чарт | [prometheus-community/kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) |
| Версия чарта | **91.4.1**, `appVersion v0.94.0` ([Chart.yaml](https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/Chart.yaml)) |
| Репозиторий | `https://prometheus-community.github.io/helm-charts` либо OCI `ghcr.io/prometheus-community/charts/kube-prometheus-stack` |
| CRD-только чарт | [prometheus-operator-crds](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-operator-crds) **32.0.0** (`appVersion v0.94.0`) |

CRD Prometheus Operator (группа `monitoring.coreos.com`): `Prometheus`,
`PrometheusAgent`, `Alertmanager`, `ThanosRuler`, `ServiceMonitor`, `PodMonitor`,
`Probe`, `ScrapeConfig`, `PrometheusRule`, `AlertmanagerConfig`.

Что **бандлит** kube-prometheus-stack: собственно prometheus-operator,
Prometheus, Alertmanager, а как зависимости — `kube-state-metrics` 8.5.0,
`prometheus-node-exporter` 4.57.0, Grafana 13.2.5 (`oci://ghcr.io/grafana-community/helm-charts`)
и CRD-сабчарт `crds`. Важная оговорка из README: чарт **не** ставит Prometheus
Adapter и black-box exporter, хотя проект [kube-prometheus](https://github.com/prometheus-operator/kube-prometheus)
включает и их, а также готовые дашборды и правила (rules) из upstream-миксинов.

Структура values: верхнеуровневые ключи `prometheus`, `alertmanager`,
`kubeStateMetrics`, `nodeExporter`, `grafana`, `prometheusOperator`, `kubeEtcd`,
`kubeApiServer`, `kubeControllerManager`, `kubeScheduler`, `kubeProxy`,
`coreDns`/`kubeDns`, `kubelet`, `defaultRules`, `additionalPrometheusRulesMap`.
Дашборды приезжают ConfigMap'ами для сайдкара Grafana
(`grafana.sidecar.dashboards.enabled: true`), datasource — тоже через сайдкар
(`grafana.sidecar.datasources`, по умолчанию Prometheus).

Апгрейд и версионирование (первоисточник — README):

- Helm **не обновляет CRD** при `helm upgrade`; их обновляют вручную
  ([Helm docs on CRDs](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/)).
- Мажорный бамп версии чарта = несовместимое изменение, требующее ручных действий;
  `appVersion` чарта соответствует версии prometheus-operator, а значит и CRD.
- **Для Argo CD**: CRD оператора больше лимита аннотации
  `kubectl.kubernetes.io/last-applied-configuration` в 262144 байта
  (`crd-prometheuses.yaml` ~840 KiB), поэтому client-side apply падает с
  `metadata.annotations: Too long`; требуется **`ServerSideApply=true`**.

### 2.2 VictoriaMetrics Operator

| | |
|---|---|
| Проект | [VictoriaMetrics/operator](https://github.com/VictoriaMetrics/operator) |
| Версия | [v0.74.1](https://github.com/VictoriaMetrics/operator/releases/tag/v0.74.1) (2026-08-04) |
| Лицензия | Apache-2.0 |
| Чарт оператора | `victoria-metrics-operator` **0.67.3** (`appVersion v0.74.1`) |
| Чарт CRD | `victoria-metrics-operator-crds` **0.14.0** (`appVersion v0.74.0`) |
| Репозиторий | `https://victoriametrics.github.io/helm-charts` |
| Документация | [docs.victoriametrics.com/operator](https://docs.victoriametrics.com/operator/) |

Кроме зеркальных CRD из §1.3, оператор умеет:

- **читать `ServiceMonitor`/`PodMonitor`/`PrometheusRule`/`Probe`/`ScrapeConfig`**
  от prometheus-operator (см. §3.1);
- поддерживать `VMScrapeConfig` — аналог `ScrapeConfig` для любого service
  discovery из VictoriaMetrics;
- `VMAgent` — self-monitoring и шардинг; `VMAuth`/`VMUser` — доступ и
  multi-tenancy.

Группа CRD — `operator.victoriametrics.com`, основные версии `v1beta1`
(есть также `v1`/`v1alpha1`).

### 2.3 victoria-metrics-k8s-stack и одиночные чарты

| Чарт | Версия (release) | appVersion | Назначение |
|---|---|---|---|
| [victoria-metrics-k8s-stack](https://github.com/VictoriaMetrics/helm-charts/tree/master/charts/victoria-metrics-k8s-stack) | **0.92.1** | v1.151.0 | all-in-one мониторинг кластера |
| [victoria-metrics-operator](https://github.com/VictoriaMetrics/helm-charts/tree/master/charts/victoria-metrics-operator) | 0.67.3 | v0.74.1 | только оператор |
| [victoria-metrics-operator-crds](https://github.com/VictoriaMetrics/helm-charts/tree/master/charts/victoria-metrics-operator-crds) | 0.14.0 | v0.74.0 | только CRD |
| [victoria-metrics-single](https://github.com/VictoriaMetrics/helm-charts/tree/master/charts/victoria-metrics-single) | 0.46.0 | v1.151.0 | одиночная TSDB |
| [victoria-metrics-cluster](https://github.com/VictoriaMetrics/helm-charts/tree/master/charts/victoria-metrics-cluster) | 0.50.0 | v1.151.0 | кластерная TSDB |

(Ветка `master` чарта `victoria-metrics-k8s-stack` уже содержит `0.93.0` /
`v1.152.0`, но это ещё не опубликованный релиз; в Helm-индексе — 0.92.1.)

[Документация k8s-stack](https://docs.victoriametrics.com/helm/victoria-metrics-k8s-stack/)
описывает его так: «all-in-one решение… ставит несколько dependency-чартов —
`grafana`, `node-exporter`, `kube-state-metrics` и `victoria-metrics-operator`.
Также ставит Custom Resources `VMSingle`, `VMCluster`, `VMAgent`, `VMAlert` для
метрик, опционально `VLSingle`/`VLCluster`/`VLAgent` для логов и
`VTSingle`/`VTCluster` для трейсов». Ключевые факты:

- Метрики собирает **`VMAgent`**; по умолчанию чарт ставит `VMSingle` как
  хранилище. Чтобы писать во внешнюю VM, ставят `vmsingle.enabled: false` и
  задают `vmagent.vmagentSpec.remoteWrite.url`.
- Чарт **ставит scrape-конфиги для компонентов Kubernetes** (kubelet, kube-proxy
  и т.д.) и «ставит кучу дашбордов и recording rules из проекта kube-prometheus».
- По умолчанию «оператор конвертирует все существующие prometheus-operator API
  объекты» (`victoria-metrics-operator.operator.disable_prometheus_converter: false`).
- Дашборды по умолчанию раздаются ConfigMap'ами для сайдкара Grafana; режим CRD
  включается `defaultDashboards.grafanaOperator.enabled: true` (требует
  grafana-operator). Источники дашбордов перечислены в values: собственные
  дашборды VictoriaMetrics, `kubernetes-views-*` из
  [dotdc/grafana-dashboards-kubernetes](https://github.com/dotdc/grafana-dashboards-kubernetes),
  `node-exporter-full` из [rfmoz/grafana-dashboards](https://github.com/rfmoz/grafana-dashboards)
  и дашборды из [prometheus-operator/kube-prometheus](https://github.com/prometheus-operator/kube-prometheus).
- **Argo CD-нюансы** (важно для этого репозитория, т.к. Argo уже стоит): без
  cert-manager вебхук-сертификаты оператора перерендериваются на каждом sync
  (Helm `lookup` не работает в Argo), пароль Grafana меняется на каждом sync, а
  на дашбордах ловится `metadata.annotations: Too long`. Лечится
  `ignoreDifferences` + `RespectIgnoreDifferences=true` — примеры в документации
  чарта.

### 2.4 Grafana Operator vs Helm-чарт Grafana

**Grafana Operator** ([grafana/grafana-operator](https://github.com/grafana/grafana-operator),
[v5.25.0](https://github.com/grafana/grafana-operator/releases/tag/v5.25.0),
Apache-2.0, OCI-чарт `oci://ghcr.io/grafana/helm-charts/grafana-operator --version 5.25.0`)
управляет Grafana и её объектами как CRD (группа `grafana.integreatly.org/v1beta1`):

| CRD | Что описывает |
|---|---|
| `Grafana` | инстанс Grafana (сам deployment/конфиг) |
| `GrafanaDatasource` | datasource |
| `GrafanaDashboard` | дашборд (inline JSON, из URL, ConfigMap, jsonnet, OCI) |
| `GrafanaFolder`, `GrafanaLibraryPanel` | папки и библиотечные панели |
| `GrafanaAlertRuleGroup`, `GrafanaContactPoint`, `GrafanaNotificationPolicy*`, `GrafanaMuteTiming`, `GrafanaNotificationTemplate` | алертинг Grafana |
| `GrafanaServiceAccount`, `GrafanaManifest` | служебное |

**Helm-чарт Grafana** — datasource'ы и дашборды приезжают через **provisioning**:
сайдкар читает ConfigMap'ы с лейблом `grafana_dashboard`, а datasource'ы — из
файла provisioning (или тоже сайдкаром). Именно так это и устроено сейчас в
`apps/grafana/`.

Текущий раскол в источниках чарта (проверено):

- `grafana/helm-charts` (`https://grafana.github.io/helm-charts`) → чарт `grafana`
  **10.5.15**, `appVersion 12.3.1`;
- `grafana-community/helm-charts` (`oci://ghcr.io/grafana-community/helm-charts`)
  → чарт `grafana` **13.2.5**, `appVersion 13.2.2` — именно её пиннит
  kube-prometheus-stack 91.4.1 и упоминает документация VM k8s-stack.

Оба репозитория живые; для новых развёртываний ориентироваться стоит на
`grafana-community` (её использует актуальный kube-prometheus-stack), но для уже
работающего Grafana 13.2.0 в этом репозитории менять источник чарта нет причины.

### 2.5 Сопутствующие компоненты

| Компонент | Роль | Версия | Лицензия |
|---|---|---|---|
| [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics) | состояние объектов API как метрики `kube_*` | v2.20.0 (чарт 8.5.0) | Apache-2.0 |
| [node-exporter](https://github.com/prometheus/node_exporter) | метрики хоста (`node_*`) | v1.12.1 (чарт 4.57.0) | Apache-2.0 |
| [metrics-server](https://github.com/kubernetes-sigs/metrics-server) | Metrics API для HPA/`kubectl top` | v0.9.0 | Apache-2.0 |

В k0s metrics-server идёт из коробки (см. `k8s/k0s/README.md`), поэтому трогать
его не нужно.

---

## 3. 🔗 Совместимость и интеграции (точно, с первоисточниками)

### 3.1 Может ли VM Operator читать prometheus-operator CRD?

**Да.** Первоисточник — [Integrations: Prometheus](https://docs.victoriametrics.com/operator/integrations/prometheus/).
«VictoriaMetrics operator has api capability with it. So you can use familiar CRD
objects: `ServiceMonitor`, `PodMonitor`, `PrometheusRule`, `Probe`,
`AlertmanagerConfig`».

Точные настройки и ограничения:

- Поддерживаемые версии исходных CRD: `ServiceMonitor`, `PodMonitor`,
  `PrometheusRule`, `Probe` — `monitoring.coreos.com/v1`; `AlertmanagerConfig` —
  `monitoring.coreos.com/v1alpha1`. В списке конвертации фигурирует и
  `ScrapeConfig`.
- **CRD Prometheus Operator не поставляются с оператором VM** — их нужно
  поставить отдельно (например, чартом `prometheus-operator-crds`).
- По умолчанию оператор **конвертирует** исходные объекты в свои (в том же
  namespace), **синхронизирует** обновления (включая лейблы), но **НЕ удаляет**
  сконвертированные объекты после удаления оригиналов — можно безопасно
  мигрировать или держать два оператора одновременно.
- Отключение конвертации по видам — флаг `-controller.disableReconcileFor` со
  значениями `PodMonitor|ServiceMonitor|PrometheusRule|Probe|ScrapeConfig`; в
  Helm — `operator.disable_prometheus_converter: true`.
- Связь жизненных циклов (удалять VM-объект вместе с исходным) —
  `VM_ENABLEDPROMETHEUSCONVERTEROWNERREFERENCES=true` либо
  `operator.enable_converter_ownership: true`.
- Управление синхронизацией — аннотации `operator.victoriametrics.com/ignore-prometheus-updates: enabled`
  и `operator.victoriametrics.com/merge-meta-strategy: prefer-prometheus | prefer-victoriametrics | merge-prometheus-priority | merge-victoriametrics-priority`.
- Фильтры метаданных — `VM_FILTERPROMETHEUSCONVERTERLABELPREFIXES` и
  `VM_FILTERPROMETHEUSCONVERTERANNOTATIONPREFIXES`.
- **Argo CD**: `VM_PROMETHEUSCONVERTERADDARGOCDIGNOREANNOTATIONS=true` добавляет
  конвертированным объектам аннотации Argo ignore, чтобы не было out-of-sync.
- Есть и авто-обнаружение `prometheus.io/*`-аннотаций через специальный
  `VMPodScrape`/`VMServiceScrape` с relabel'ами — примеры в той же статье.

Практический вывод: можно держать привычные `ServiceMonitor` в приложениях
(экосистема пишет их по умолчанию) и при этом хранить данные в VictoriaMetrics.

### 3.2 Подходят ли дашборды kube-prometheus-stack к VictoriaMetrics?

Да. MetricsQL **обратно совместим с PromQL**: «MetricsQL is backwards-compatible
with PromQL, so Grafana dashboards backed by Prometheus datasource should work the
same after switching from Prometheus to VictoriaMetrics»
([MetricsQL](https://docs.victoriametrics.com/victoriametrics/metricsql/)).
Есть осознанные отличия (`increase`/`rate` считают точнее, не экстраполируют
результат), но они не ломают панели.

Технически «навести чарт на VM» можно двумя способами:

1. В самом kube-prometheus-stack: сайдкар datasource'ов
   (`grafana.sidecar.datasources`) по умолчанию отдаёт Prometheus; переопределить
   URL можно через `grafana.sidecar.datasources.url`, а дополнительные
   datasource'ы — через `grafana.additionalDataSources: []` или
   `grafana.additionalDataSourcesString` (всё в
   [values.yaml](https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/values.yaml)).
2. Проще — вообще не брать Grafana из kube-prometheus-stack, а оставить свою и
   прописать VM datasource (как уже сделано в `apps/grafana/`).

Важно: дашборды kube-prometheus-stack — это дашборды **kubernetes-mixin** и
upstream-проектов, они не требуют Prometheus как таковой, им нужен
Prometheus-совместимый datasource (см. §4).

### 3.3 Grafana Operator / чарт с VM datasource

Да. VM реализует [Prometheus querying API](https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/):
`/api/v1/query`, `/api/v1/query_range`, `/api/v1/series`, `/api/v1/labels`,
`/api/v1/label/.../values`, `/api/v1/status/tsdb`, `/api/v1/targets`,
`/api/v1/metadata`, `/federate`. «…can be queried from Prometheus-compatible
clients such as Grafana or curl». Все хендлеры работают и с префиксом
`/prometheus`. Поэтому в Grafana datasource имеет смысл тип **`prometheus`**
(ровно так и сделано в `apps/grafana/k8s/grafana-provisioning.configmap.yaml`).
Отдельный плагин [VictoriaMetrics datasource](https://docs.victoriametrics.com/victoriametrics/integrations/grafana/datasource/)
нужен для фич вроде `WITH`-выражений и метрик самого datasource, но для базовых
дашбордов он не обязателен.

С Grafana Operator то же самое: `GrafanaDatasource` с `spec.type: prometheus` и
`url` на VM. Дополнительно: VM принимает `extra_label`/`extra_filters[]` от
auth-прокси (vmauth) — удобно для ограничения видимости.

### 3.4 Смешанные стеки

| Схема | Возможно? | Механика |
|---|---|---|
| Prometheus CRD → vmagent → VM storage | Да | конвертер VM Operator (§3.1); либо vmagent сам читает `ServiceMonitor` через `prometheus.operator.servicemonitors` (Alloy), но это уже Alloy-мир |
| Prometheus CRD + прометеев оператор + vmalert | Да | `PrometheusRule` конвертируется в `VMRule`; `vmalert` умеет читать правила и шлёт алерты в Alertmanager ([vmalert](https://docs.victoriametrics.com/victoriametrics/vmalert/)) |
| vmalert ↔ Alertmanager | Да | `vmalert -notifier.url=...`; у VM есть и свой `VMAlertmanager` с тем же протоколом ([VMAlert](https://docs.victoriametrics.com/operator/resources/vmalert/), [VMAlertmanager](https://docs.victoriametrics.com/operator/resources/vmalertmanager/)) |
| Grafana как единый UI над Prometheus **и** VM | Да | два datasource'а типа `prometheus` |
| `Prometheus` CR (TSDB) → VM через remote_write | Да | `spec.remoteWrite` в CR; или vmagent двойной записью |

Ключевая практическая мысль: **backend и scraper развязаны**. Можно оставить
kube-prometheus-stack ради его `ServiceMonitor`-экосистемы, но не хранить данные
в Prometheus, а отправлять remote_write в VM — хотя на одной ноде это лишний
компонент.

### 3.5 metrics-server: другая задача

Официальная позиция из [README metrics-server](https://github.com/kubernetes-sigs/metrics-server):
«Metrics Server is meant only for autoscaling purposes. For example, don't use it
to forward metrics to monitoring solutions, or as a source of monitoring solution
metrics. In such cases please collect metrics from Kubelet `/metrics/resource`
endpoint directly». Сборщик метрик API (`Metrics API`) обслуживает HPA/VPA и
`kubectl top`; он не заменяет и не дополняет полноценный мониторинг. В k0s он
уже есть — оставить его в покое.

### 3.6 kube-state-metrics, node-exporter, cAdvisor: от бэкенда не зависят

Все три отдают обычный Prometheus-exposition, поэтому одинаково работают и с
Prometheus, и с vmagent: метрики `kube_*`, `node_*`, `container_*` имеют одни и
те же имена и лейблы. Разница только в способе обнаружения:

- `kube-state-metrics` и `node-exporter` — обычные `Service`+порт → в VM-мире
  `VMServiceScrape`, в Prometheus-мире `ServiceMonitor`; k8s-stack/kube-prometheus
  ставят их сами вместе с дашбордами.
- kubelet/cAdvisor (`/metrics`, `/metrics/cadvisor`) — в Prometheus-мире дефолтные
  ServiceMonitor'ы kubelet; в VM-мире — `VMNodeScrape` (или ServiceMonitor,
  который сконвертирует оператор). cAdvisor-дашборды (`container_*`) требуют
  доступа к `/metrics/cadvisor` — в текущем `vmagent-rbac.yaml` права уже выданы.

**Специфика k0s**: control-plane компоненты (kube-apiserver, kube-controller-manager,
kube-scheduler, etcd) k0s запускает не как обычные поды, а как процессы под
супервизором самого k0s: «As a single binary, k0s acts as the process supervisor
for all other control plane components. As such, there is no container engine or
kubelet running on controllers by default»
([k0s architecture](https://docs.k0sproject.io/stable/architecture/)). Значит
дефолтные ServiceMonitor'ы `kubeEtcd`/`kubeControllerManager`/`kubeScheduler`/
`kubeProxy` из kube-prometheus-stack могут не найти цели или упереться в
`127.0.0.1`-адреса. Это надо проверять на кластере и, скорее всего, выключать
соответствующие `*.enabled: false` (а `kubeApiServer` скорее всего заработает —
он доступен через `kubernetes` Service). **Живой проверки не делалось.**

### 3.7 OTLP: коротко

И VM, и Prometheus принимают OTLP (VM — `/opentelemetry/v1/metrics`, Prometheus —
флагом `--web.enable-otlp-receiver`). Детали, статусы и семантику resource-атрибутов
см. в [observability-standards-and-approaches.md](../observability-standards-and-approaches.md)
§5. Для этого репозитория важно, что push OTLP от приложений попадает в любой из
бэкендов, а `otel-collector` уже скрейпится отдельным job'ом.

---

## 4. 📊 Готовые дашборды

### 4.1 kubernetes-mixin

Репозиторий переехал: канонический —
[kubernetes-sigs/kubernetes-mixin](https://github.com/kubernetes-sigs/kubernetes-mixin)
(старый `kubernetes-monitoring/kubernetes-mixin` редиректит; это прямо написано
в README). Лицензия Apache-2.0, последний тег —
[version-1.5.6](https://github.com/kubernetes-sigs/kubernetes-mixin/releases/tag/version-1.5.6).

Это «набор Grafana-дашбордов и Prometheus-алертов для Kubernetes», генерируемый
из jsonnet. Дашборды: `k8s-resources-cluster/namespace/node/pod/workload/workloads-namespace/multicluster`,
`nodes`/`node-rsrc-use`/`node-cluster-rsrc-use`, `persistentvolumesusage`,
`namespace-by-pod`, `namespace-by-workload`, `pod-total`, `cluster-total`,
`workload-total`, `apiserver`, `controller-manager`, `scheduler`, `proxy`,
`kubelet`, windows-варианты. Правила (recording) — из `rules/`: `apps`,
`node`, `kubelet`, `kube_scheduler`, `kube_apiserver-*`, windows.

**Критично для дашбордов**: значительная часть панелей kubernetes-mixin строится
**на recording rules**, а не на сырых метриках. Примеры имён:
`cluster:node_cpu:ratio_rate5m`,
`namespace_cpu:kube_pod_container_resource_requests:sum`,
`cluster_quantile:apiserver_request_sli_duration_seconds:histogram_quantile`.
Если rules не установлены — панели пустые. Именно эти дашборды и правила
kube-prometheus-stack кладёт внутрь чарта (`kube-prometheus-stack/hack/` собирает
их из upstream-миксинов, см. [hack/README.md](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack/hack)).

### 4.2 Что бандлит kube-prometheus-stack (проверено по дереву чарта)

`templates/grafana/dashboards-1.14/`: alertmanager-overview, apiserver,
cluster-total, controller-manager, etcd, grafana-overview, k8s-coredns,
k8s-resources-cluster/multicluster/namespace/node/nodes-overview/pod,
k8s-resources-windows-*, k8s-resources-workload(s-namespace),
k8s-windows-*, kubelet, namespace-by-pod, namespace-by-workload,
node-cluster-rsrc-use, node-rsrc-use, nodes, persistentvolumesusage, pod-total,
prometheus-remote-write, prometheus, proxy, scheduler, workload-total. Это
kubernetes-mixin + дашборды компонентов.

### 4.3 «Kubernetes / Views» от dotdc (IDs проверены на Grafana.com)

[dotdc/grafana-dashboards-kubernetes](https://github.com/dotdc/grafana-dashboards-kubernetes)
(Apache-2.0) — именно этот набор использует VM k8s-stack для «views»-дашбордов.
README прямо говорит: дашборды сделаны и протестированы под kube-prometheus-stack,
но работают с любым стеком, где есть **kube-state-metrics** и
**prometheus-node-exporter**; у них есть переменная `Prometheus Datasource`.

| ID | Название (og:title с grafana.com) | Файл |
|---|---|---|
| [15757](https://grafana.com/grafana/dashboards/15757/) | Kubernetes / Views / Global | k8s-views-global.json |
| [15758](https://grafana.com/grafana/dashboards/15758/) | Kubernetes / Views / Namespaces | k8s-views-namespaces.json |
| [15759](https://grafana.com/grafana/dashboards/15759/) | Kubernetes / Views / Nodes | k8s-views-nodes.json |
| [15760](https://grafana.com/grafana/dashboards/15760/) | Kubernetes / Views / Pods | k8s-views-pods.json |
| [15761](https://grafana.com/grafana/dashboards/15761/) | Kubernetes / System / API Server | k8s-system-api-server.json |
| [15762](https://grafana.com/grafana/dashboards/15762/) | Kubernetes / System / CoreDNS | k8s-system-coredns.json |

Важно: это **не** kubernetes-mixin и, по заявлению автора, они не требуют
mixins-правил (в отличие от §4.1) — строятся на `kube_*`/`node_*`/`container_*`.
Именно поэтому они хороший выбор для текущего homelab.

### 4.4 Другие проверенные ID и их требования

| ID | Название (og:title) | Что нужно |
|---|---|---|
| [315](https://grafana.com/grafana/dashboards/315/) | Kubernetes cluster monitoring (via Prometheus) | старый классический, kube-state-metrics + node-exporter |
| [6417](https://grafana.com/grafana/dashboards/6417/) | Kubernetes Cluster (Prometheus) | kube-state-metrics + node-exporter |
| [13332](https://grafana.com/grafana/dashboards/13332/) | kube-state-metrics-v2 | только kube-state-metrics |
| [14205](https://grafana.com/grafana/dashboards/14205/) | Kubernetes Cluster Monitoring (via Prometheus) | kube-state-metrics + node-exporter |
| [1860](https://grafana.com/grafana/dashboards/1860/) | Node Exporter Full | только node-exporter |
| [8588](https://grafana.com/grafana/dashboards/8588/) | 1. Kubernetes Deployment Statefulset Daemonset metrics | только kube-state-metrics |
| [11176](https://grafana.com/grafana/dashboards/11176/) | VictoriaMetrics - cluster | метрики VM-кластера |

Проверено заодно: `15756` — **не** дашборд (`404 Page not found`), а `15763`–`15767`
— это OPA Gatekeeper, Nomad, IPMI Exporter, Slow Logs и Chrony, то есть к
Kubernetes они отношения не имеют. Не стоит доверять спискам ID из блогов.

### 4.5 Официальные дашборды VictoriaMetrics

В репозитории VictoriaMetrics — папка
[dashboards/](https://github.com/VictoriaMetrics/VictoriaMetrics/tree/master/dashboards):
`victoriametrics.json` (single-node), `victoriametrics-cluster.json`, `vmagent.json`,
`vmalert.json`, `vmauth.json`, `operator.json`, `backupmanager.json`,
`clusterbytenant.json`, `query-stats.json`, `metrics-explorer.json`,
`alert-statistics.json`. В подпапке
[dashboards/vm](https://github.com/VictoriaMetrics/VictoriaMetrics/tree/master/dashboards/vm)
лежат те же дашборды, но под datasource-плагин VictoriaMetrics. Опубликованная
копия — на [grafana.com/orgs/victoriametrics](https://grafana.com/orgs/victoriametrics/dashboards).

Их переменные: `ds` (datasource), `job`, `instance`, `version`, а метрики —
self-metrics самих компонентов (`vm_app_version`, `vmagent_*`, `vm_*`). Это ровно
то, что нужно, чтобы смотреть на собранный стек.

### 4.6 Чем отличаются «сырые» и «rules-зависимые» дашборды

| Категория | Примеры | Зависимости | Что ожидать сейчас |
|---|---|---|---|
| На сырых метриках | dotdc 15757–15762, 315/6417/14205, 1860, 13332, 8588 | kube-state-metrics, node-exporter, cAdvisor | заработают сразу (уже скрейпятся; проверить лейбл `cluster`) |
| На recording rules | kubernetes-mixin `k8s-resources-*`, `nodes`, `apiserver` и т.д. | правила `cluster:*`, `namespace_*:*` + kube-state-metrics | панели будут пустыми без установки `VMRule`/`PrometheusRule` |
| Self-metrics VM | 11176, VM `dashboards/*` | vmagent/VM/vmalert | заработают, если скрейпить свои компоненты |
| Control-plane | `etcd`, `controller-manager`, `scheduler`, `proxy` | доступность endpoints | на k0s под вопросом (§3.6) |

Переменные datasource в дашбордах — стандартные: dotdc использует переменную
`datasource` типа `datasource` (query `prometheus`), node-exporter-full —
`ds_prometheus`, VM-дашборды — `ds`. Так как в Grafana VM подключена как
datasource типа `prometheus`, все они совместимы.

---

## 5. 🔁 Миграция: текущий `scrape.yml` → CRD, построчно

Ниже — концептуальное соответствие джобов из
`apps/victoria-metrics/k8s/vmagent.configmap.yaml`. Столбец «CRD» подразумевает
развёрнутый VM Operator + `VMAgent` CR (или, альтернативно, prometheus-operator CRD,
которые конвертер VM прочитает).

| В `scrape.yml` сейчас | Kubernetes-native эквивалент | Комментарий |
|---|---|---|
| `global.scrape_interval: 15s` | `VMAgent.spec.scrapeInterval` (и per-endpoint `interval`) | глобальный дефолт переезжает в спек |
| `job netdata` (static, `metrics_path: /api/v1/allmetrics`, params) | `VMStaticScrape` (внешняя/не-сервисная цель) | для целей вне Service-модели; либо `VMServiceScrape`, если netdata — Service |
| `job node-exporter` (static) | `VMServiceScrape`, `endpoints[].port: metrics` | Service и порт объявляет сам node-exporter |
| `job kube-state-metrics` (static) | `VMServiceScrape` | есть в дефолтах kube-prometheus/VM k8s-stack |
| `job kubelet` (`kubernetes_sd: role: node`, `:10250`, bearer, insecure TLS) | `VMNodeScrape` | k8s-stack ставит его сам; право на `/metrics` уже есть в `vmagent-rbac.yaml` |
| `job cadvisor` (`/metrics/cadvisor`) | `VMNodeScrape` | то же |
| `job victoriametrics` / `vmagent` (self) | `VMServiceScrape` (или self-monitoring в чарте) | self-metrics |
| `job traefik`, `authentik`, `wud`, `gatus`, `synapse`, `immich`, `livekit`, `grafana`, `jitsi-jvb`, `oauth2-proxy`, `infisical`, `otel-collector`, `jellyfin`, `nextcloud` (static, без auth) | по одному `VMServiceScrape` на сервис | intent «у меня `/metrics`» живёт рядом с приложением, а не в общем конфиге |
| Авторизуемые цели: `local-ai` (Bearer), `home-assistant` (Bearer, `/api/prometheus`), `uptime-kuma` (basic), `navidrome` (`metrics_path` с секретом), `dawarich` (https + basic), `forgejo` (Bearer), `technitium` (Bearer), `stalwart` (basic) | `endpoints[].authorization` / `basicAuth` / `bearerTokenSecret`, `tlsConfig`, `metrics_path` в CRD | **Меняется модель секретов**: вместо env-подстановки `%{VAR}` — `Secret`-ссылки, которые читает оператор; `%`-трюк уходит |
| `job cnpg` (`kubernetes_sd: role: pod`, keep по `cnpg.io/cluster`, relabel, drop служебных `datname`) | `VMPodScrape` с `selector.matchLabels`, `podMetricsEndpoints[].port: metrics`, `relabelings`/`metricRelabelings` | CNPG сам рекомендует **ручной** `PodMonitor`; авто-создание `.spec.monitoring.enablePodMonitor` помечено deprecated ([CNPG monitoring](https://cloudnative-pg.io/docs/current/monitoring/)). Конвертер VM прочитает `PodMonitor` |
| `job postgres` / `redis` / `mysql` (static-экспортёры) | `VMServiceScrape` на каждый Service экспортёра | один CRD на экспортёр (или общий по лейблу) |
| правил алертинга нет | `VMRule` + `VMAlert` + `VMAlertmanager` | это отдельный пробел: сейчас алертит Gatus/Uptime Kuma, метрического алертинга нет |

Что появится «бесплатно» после перехода: динамическое перечитывание конфига без
рестарта пода, per-service ownership (сервис сам владеет своим CRD в своём
namespace), возможность точечно включать конвертер и дефолтные правила.

Что усложнится: секреты перестанут быть env-шаблонами; появится контроллер и
CRD, которые надо обновлять; в Argo CD добавятся `RespectIgnoreDifferences` и
`ServerSideApply` для тяжёлых CRD.

---

## 6. 🏠 Рекомендация для этого homelab

### 6.1 Компромисс: три варианта

| Вариант | Плюсы | Минусы | Вердикт |
|---|---|---|---|
| **Полный `victoria-metrics-k8s-stack`** | канонический VM-way: свой оператор, VMAgent, VMSingle, VMAlert, дашборды, правила; меньше ручной работы | поставит **свои** VMSingle/VMAgent/Grafana/node-exporter/KSM → конфликт с уже развёрнутыми; на одной ноде это заметный расход; Argo CD-нюансы | для «с нуля», сейчас — нет |
| **kube-prometheus-stack** | самая большая экосистема `ServiceMonitor`/дашбордов/правил | тянет Prometheus TSDB (выше RAM/диск, чем VM), дублирует уже существующие Grafana/KSM/node-exporter; надо переучиваться с MetricsQL | нет |
| **Только VM Operator + сохранить VMSingle/Grafana** | инкрементально, без дублей, VM остаётся; CRD-паттерн появляется; конвертер читает чужие ServiceMonitor | нужно руками перевести vmagent Deployment → `VMAgent` CR и джобы → scrape-CRD; оператор — ещё один контроллер | **да, рекомендуемый путь** |

### 6.2 План по этапам

**Этап 1 — фундамент (низкий риск).** Поставить
`victoria-metrics-operator-crds` + `victoria-metrics-operator` (через Argo CD
Application, как уже сделан kube-state-metrics). Оставить работающие VMSingle и
Grafana как есть. Проверить, что CRD появились, а webhook не роняет кластер
(в VM-чарте `admissionWebhooks.policy: Ignore` — разумный дефолт для одной ноды).

**Этап 2 — перевести сборщик.** Заменить `vmagent.deployment.yaml` +
`vmagent.configmap.yaml` на `VMAgent` CR (тот же образ `vmagent:v1.150.0` →
позже обновить) и перенести джобы по таблице §5. Начать с «сырых»:
node-exporter, kube-state-metrics, kubelet/cAdvisor (`VMNodeScrape`), app-метрики.
Секреты авторизуемых целей — `Secret`-ссылки в CRD. Это самый трудоёмкий шаг;
делать его в отдельном namespace-owner'е и проверять `up` в VM.

**Этап 3 — правила и алертинг.** Добавить `VMRule` (можно взять готовые
kubernetes-mixin rules, сгенерировав `PrometheusRule` jsonnet → YAML), `VMAlert`
и, если нужен маршрут уведомлений, `VMAlertmanager`/внешний Alertmanager. Это
закроет разрыв «есть метрики, но нет алертинга».

**Этап 4 — дашборды.** В Grafana (остаётся Deployment+provisioning) добавить
дашборды как ConfigMap'ы с лейблом `grafana_dashboard` — проще всего dotdc
15757–15760 (они на сырых метриках) + VM self-metrics. Для rules-зависимых
kubernetes-mixin дашбордов сначала поставить соответствующие `VMRule`.

**Этап 5 (опционально).** Перевести `VMSingle` Deployment → `VMSingle` CR
(управляемые PVC/retention), `VMSingle`-му дашборд. Grafana Operator брать
только если захочется дашборды-как-CRD: иначе provisioning ConfigMap проще и
дешевле на одной ноде.

### 6.3 Почему не полный k8s-stack прямо сейчас

У вас уже есть `VMSingle` + `vmagent` + `Grafana` + `node-exporter` как
Deployments и `kube-state-metrics` под Argo. Полный k8s-stack создаст
параллельные `VMSingle`/`VMAgent`/`Grafana`/`node-exporter`/KSM; два владельца
одних и тех же данных — это ровно тот пинг-понг, о котором предупреждает
`k8s/argocd/README.md`. Поэтому «Kubernetes way» здесь = **оператор + CRD
инкрементально**, а не «снести и поставить all-in-one». Если однажды захочется
чистый all-in-one, k8s-stack — правильный кандидат, но это уже осознанная
миграция, а не апгрейд.

---

## 7. ⚠️ Что не удалось проверить / открытые вопросы

- **Живых проверок на сервере не делалось.** Всё выше — по первоисточникам.
- **Доступность control-plane endpoints на k0s** (etcd, kube-controller-manager,
  kube-scheduler, kube-proxy): k0s запускает их процессами, а не подами; будут ли
  дефолтные ServiceMonitor'ы kube-prometheus-stack находить цели — нужно смотреть
  на кластере. Не проверено.
- **Точная каноничность Grafana-чарта**: активны и `grafana/helm-charts`, и
  `grafana-community/helm-charts`; актуальный kube-prometheus-stack использует
  второй. Однозначного заявления о «переезде» в первоисточниках не нашлось.
- **Версия `victoria-metrics-k8s-stack`**: в Helm-индексе 0.92.1, но в ветке
  `master` уже 0.93.0/`v1.152.0` (не выпущено). Пиновать нужно релизную 0.92.1.
- **Поведение dotdc-дашбордов с VM k8s-stack** (патч переменной `cluster` через
  `clusterMetric`): механизм виден в values, но результат на конкретном наборе
  метрик не проверялся.
- **CNPG**: авто-`PodMonitor` (`.spec.monitoring.enablePodMonitor`) помечен
  deprecated; рекомендуется ручной `PodMonitor`/`VMPodScrape`. Как именно ляжет на
  конвертер VM — не проверялось.

## Источники (первоисточники)

- Prometheus Operator: [Introduction](https://prometheus-operator.dev/docs/getting-started/introduction/),
  [Design](https://prometheus-operator.dev/docs/getting-started/design/),
  [API reference](https://prometheus-operator.dev/docs/api-reference/api/),
  [v0.94.0 release](https://github.com/prometheus-operator/prometheus-operator/releases/tag/v0.94.0)
- kube-prometheus-stack: [Chart.yaml](https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/Chart.yaml),
  [README](https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/README.md),
  [values.yaml](https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/values.yaml),
  [prometheus-operator-crds](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-operator-crds)
- [kube-prometheus](https://github.com/prometheus-operator/kube-prometheus)
- kube-state-metrics: [repo](https://github.com/kubernetes/kube-state-metrics),
  [чарт](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-state-metrics)
- node-exporter: [чарт](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-node-exporter)
- VictoriaMetrics Operator: [docs](https://docs.victoriametrics.com/operator/),
  [API](https://docs.victoriametrics.com/operator/api/),
  [VMServiceScrape](https://docs.victoriametrics.com/operator/resources/vmservicescrape/),
  [Integrations: Prometheus](https://docs.victoriametrics.com/operator/integrations/prometheus/),
  [v0.74.1](https://github.com/VictoriaMetrics/operator/releases/tag/v0.74.1)
- VictoriaMetrics: [Prometheus querying API](https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/),
  [MetricsQL](https://docs.victoriametrics.com/victoriametrics/metricsql/),
  [vmalert](https://docs.victoriametrics.com/victoriametrics/vmalert/),
  [dashboards/](https://github.com/VictoriaMetrics/VictoriaMetrics/tree/master/dashboards),
  [dashboards/vm](https://github.com/VictoriaMetrics/VictoriaMetrics/tree/master/dashboards/vm)
- victoria-metrics-k8s-stack: [docs](https://docs.victoriametrics.com/helm/victoria-metrics-k8s-stack/),
  [чарты](https://github.com/VictoriaMetrics/helm-charts)
- Grafana Operator: [repo](https://github.com/grafana/grafana-operator),
  [API](https://grafana.github.io/grafana-operator/),
  [installation](https://grafana.github.io/grafana-operator/docs/installation/),
  [v5.25.0](https://github.com/grafana/grafana-operator/releases/tag/v5.25.0)
- Grafana chart: [grafana-community](https://github.com/grafana-community/helm-charts/tree/main/charts/grafana)
- kubernetes-mixin: [kubernetes-sigs/kubernetes-mixin](https://github.com/kubernetes-sigs/kubernetes-mixin),
  [version-1.5.6](https://github.com/kubernetes-sigs/kubernetes-mixin/releases/tag/version-1.5.6)
- Dashboards: [dotdc](https://github.com/dotdc/grafana-dashboards-kubernetes),
  [rfmoz](https://github.com/rfmoz/grafana-dashboards),
  [15757](https://grafana.com/grafana/dashboards/15757/), [15758](https://grafana.com/grafana/dashboards/15758/),
  [15759](https://grafana.com/grafana/dashboards/15759/), [15760](https://grafana.com/grafana/dashboards/15760/),
  [15761](https://grafana.com/grafana/dashboards/15761/), [15762](https://grafana.com/grafana/dashboards/15762/),
  [315](https://grafana.com/grafana/dashboards/315/), [6417](https://grafana.com/grafana/dashboards/6417/),
  [13332](https://grafana.com/grafana/dashboards/13332/), [14205](https://grafana.com/grafana/dashboards/14205/),
  [1860](https://grafana.com/grafana/dashboards/1860/), [8588](https://grafana.com/grafana/dashboards/8588/),
  [11176](https://grafana.com/grafana/dashboards/11176/)
- Прочее: [metrics-server](https://github.com/kubernetes-sigs/metrics-server),
  [CNPG monitoring](https://cloudnative-pg.io/docs/current/monitoring/),
  [k0s architecture](https://docs.k0sproject.io/stable/architecture/)
