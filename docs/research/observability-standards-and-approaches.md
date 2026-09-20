# Observability: метрики, логи, трейсы — подходы, стандарты, стеки

Дата исследования: 2026-09-14. Все факты сверены с первоисточниками (официальные
документации, спецификации W3C/CNCF/IETF, GitHub-репозитории). Этот документ
о **подходах, стандартах и протоколах** — как телеметрия устроена под капотом
и как сигналы сочетаются между собой. Сравнение конкретных продуктов и выбор
стека для этого homelab — в отдельном исследовании.

**См. также: [docs/research/monitoring-systems-overview.md](monitoring-systems-overview.md)**
— сравнение продуктов (Prometheus-стек, LGTM, VictoriaMetrics, Zabbix и т.д.),
аудит уже установленных приложений и план внедрения.

## Вывод

Observability — это не «три столпа ради трёх столпов», а **конвейер с общим
контекстом**: один и тот же запрос должен быть виден в метриках (агрегированно),
в логах (дискретно), в трейсе (его путь по сервисам) и в профиле (какой код ест
CPU). Технологически всё сводится к трём принципам:

1. **Метрики — pull-first, дёшевы, но ограничены cardinality.** Формат
   exposition — текстовый 0.0.4/OpenMetrics по HTTP; стандартная модель
   Prometheus с лейблами стала lingua franca всего рынка.
2. **Логи и трейсы — push, объёмны, нуждаются в структуре и сэмплинге.** Без
   `trace_id` в логах и без структурированных полей логи почти бесполезны для
   расследования инцидентов.
3. **OpenTelemetry стал стандартом-зонтиком, который развязывает вендора.** OTLP
   стабилен для traces/metrics/logs (profiles — в разработке); коллектор —
   vendor-neutral узел маршрутизации; semantic conventions — общий словарь
   атрибутов. Инструментируй приложения один раз через OTel SDK/автоинструментирование —
   и можешь менять бэкенд (Loki↔VictoriaLogs, Tempo↔Jaeger, Prometheus↔VictoriaMetrics)
   без переписывания кода.

Практическая связка сигналов, которую стоит проектировать сразу: **exemplars
(метрика → пример-трейс), `trace_id` в логах (лог → трейс), derived fields /
trace-to-metrics (трейс ↔ метрика ↔ лог)** — всё это поддержано Grafana и
основано на открытых стандартах (W3C Trace Context, OpenMetrics exemplars,
OTLP).

---

## 1. 🏛️ Три столпа + профили: что чем измеряется

Каноническая рамка — «три столпа наблюдаемости» (метрики, логи, трейсы), к
которым OpenTelemetry добавляет четвёртый сигнал — **профили**. Спецификация
OTel описывает [профиль как набор stack traces с ассоциированными значениями
потребления ресурсов](https://opentelemetry.io/docs/specs/otel/profiles/),
собираемых непрерывным сэмплированием работающей программы (continuous
profiling — так работают [Pyroscope](https://grafana.com/docs/pyroscope/latest/)
и [Parca](https://www.parca.dev/)).

| Сигнал | Что фиксирует | Объём | Модель доставки | Аналитический вопрос |
|---|---|---|---|---|
| **Метрики** | Числовые агрегаты с лейблами, по временным точкам | Крошечный (байты на серию) | Преимущественно pull | *Что* деградировало и с *когда* |
| **Логи** | Дискретные события с текстом/структурой | Большой | Push | *Почему* это произошло, детали |
| **Трейсы** | Путь одного запроса через сервисы (span'ы) | Большой | Push | *Где именно* в цепочке вызовов |
| **Профили** | Stack traces + расход CPU/RAM/IO | Большой | Push (периодически) | *Какой код* потребляет ресурсы |

Ключевая идея: **сигналы сами по себе — силосы**; ценность появляется от
корреляции:

- **Exemplars** — связка «метрика → трейс»: к точке/бакету гистограммы
  прикрепляется идентификатор примера запроса (`trace_id`). Это часть стандарта
  [OpenMetrics](https://prometheus.io/docs/specs/om/open_metrics_spec/) и
  [Remote Write 2.0](https://prometheus.io/docs/specs/prw/remote_write_spec_2_0/)
  (exemplar — «additional information attached to some series' samples…
  typically used to attach an example trace»); Prometheus умеет отправлять
  exemplars через remote write, Grafana умеет по клику прыгать из графика в
  [Tempo](https://grafana.com/docs/tempo/latest/).
- **`trace_id`/`span_id` в логах** — связка «лог → трейс». Это первоклассные
  поля в [модели данных логов OpenTelemetry](https://opentelemetry.io/docs/specs/otel/logs/data-model/)
  (поля `TraceId`, `SpanId`, `TraceFlags`); W3C-совместимый 16-байтный
  trace-id пробрасывается через сервисы и попадает в каждую строку лога запроса.
- **Связка «трейс ↔ метрика»** — span'ы содержат duration; из них можно
  строить метрики (SLO/RED) либо в бэкенде (Grafana Tempo metric-generator,
  SpanMetrics connector в OTel Collector), либо в UI (Grafana «trace to
  metrics», [документация Tempo datasource](https://grafana.com/docs/grafana/latest/datasources/tempo/)).

---

## 2. 📈 Метрики

### 2.1 Pull vs push

| | Pull (Prometheus) | Push |
|---|---|---|
| Кто инициирует | Сервер опрашивает цели по HTTP | Приложение/агент отправляет |
| Живость цели | Видна сразу: метрика `up` | «Пустота» на графике не означает смерть |
| Service discovery | Нативно (k8s, Consul, DNS, file) | Нужно на стороне отправителя |
| Краткоживущие процессы (batch, cron) | Проблема: умер раньше скрейпа | Легко, но нужен шлюз |
| NAT/firewall | Цель должна быть достижима | Отправитель идёт наружу |
| Дублирование при HA | Два инстанса скрейпят независимо (дедупликация выше) | Двойная отправка |

Официальная позиция Prometheus: pull выбран ради простоты горизонтального
масштабирования мониторинга, обнаружения «живости» цели и наглядности
([FAQ: why do you pull rather than push](https://prometheus.io/docs/introduction/faq/#why-do-you-pull-rather-than-push)).
Push допустим только через шлюзы: [Pushgateway](https://prometheus.io/docs/practices/pushing/)
— строго для результатов batch-задач (бэкапы, cron), потому что gateway помнит
последние значения серий, пока их не удалишь вручную. Стек VictoriaMetrics
делает push полноценнее: vmagent принимает и pull, и push-протоколы
([vmagent](https://docs.victoriametrics.com/victoriametrics/vmagent/)).

### 2.2 Форматы exposition: текстовый 0.0.4 и OpenMetrics

**Exposition format** — то, что отдаёт приложение на `/metrics`. Сегодня их два:

- **Текстовый формат версии 0.0.4** — исторический де-факто стандарт; читаемый
  построчно формат `metric_name{label="value"} 123 [timestamp]` со служебными
  строками `# HELP` и `# TYPE`
  ([exposition formats](https://prometheus.io/docs/instrumenting/exposition_formats/)).
- **OpenMetrics** — эволюция текстового формата, вынесенная в отдельную
  спецификацию и принятую Prometheus как нормативную
  ([OpenMetrics 1.0 spec](https://prometheus.io/docs/specs/om/open_metrics_spec/)).
  Добавляет: явный `# UNIT`, `# EOF`-терминатор, типы `info` и `stateset`,
  «gauge histograms» и **exemplars** (`histogram_bucket{...} 0.05 # {trace_id="..."} 17.0 1520475121000`).
  Ведётся работа над [OpenMetrics 2.0](https://prometheus.io/docs/specs/om/open_metrics_spec_2_0/)
  (гайд по миграции клиентских библиотек:
  [migration guide](https://prometheus.io/docs/guides/open_metrics_2_0_migration/)).
- С Prometheus 2.0 доступен и **protobuf-формат** exposition через HTTP content
  negotiation; в Prometheus 3.x появился также экспоненциальный формат нативных
  гистограмм ([native histograms](https://prometheus.io/docs/specs/native_histograms/)).

**Типы метрик** (общие для обоих форматов):
[counter, gauge, histogram, summary](https://prometheus.io/docs/concepts/metric_types/) —

| Тип | Семантика | Типичная ошибка |
|---|---|---|
| Counter | Монотонно растёт; для «скорости» применяют `rate()` | Ставить на убывающую величину; не сбрасывать при рестарте |
| Gauge | Текущее значение (может расти/падать) | Пытаться суммировать историю |
| Histogram | Серверные бакеты + `sum`/`count` → гистограмма вычисляется на сервере, можно агрегировать | Слишком много бакетов = cardinality |
| Summary | Клиентские квантили, точно, но **не агрегируются** между инстансами | Использовать, когда нужен p99 по всем репликам — тогда histogram |

Батл-тест квантилей: [histograms and summaries](https://prometheus.io/docs/practices/histograms/) —
правило: «если нужны агрегируемые квантили — histogram; если одиночный инстанс
и точность критична — summary».

### 2.3 Паттерны экспортеров

- **In-app `/metrics`** — библиотека-клиент в процессе приложения; лучший
  вариант для своего кода ([client libraries](https://prometheus.io/docs/instrumenting/clientlibs/)).
- **Exporters** — отдельный процесс рядом с тем, что нельзя поменять (БД,
  железо, софт): [каталог](https://prometheus.io/docs/instrumenting/exporters/).
  Каноничные: node_exporter (хост), [blackbox_exporter](https://github.com/prometheus/blackbox_exporter)
  (HTTP/TCP/ICMP/DNS-пробы), [snmp_exporter](https://github.com/prometheus/snmp_exporter)
  (сетевое железо по SNMP).
- **Multi-target pattern** — один exporter-процесс опрашивает много целей,
  передавая цель параметром (`/probe?target=...`); так работают blackbox/snmp:
  [guide](https://prometheus.io/docs/guides/multi-target-exporter/).
- **Pushgateway** — для batch-задач, см. §2.1 ([когда использовать](https://prometheus.io/docs/practices/pushing/)).
- **MQTT-паттерн** — IoT-датчики, не имеющие HTTP-эндпоинта, публикуют в
  MQTT-брокер, а мост (например, community [mqtt_exporter](https://github.com/hikhvar/mqtt2prometheus))
  конвертирует подписки в метрики; это классический «push-в-брокер → pull-из-брокера»
  развязывающий паттерн.

### 2.4 Remote Write 1.0 и 2.0

[Remote Write](https://prometheus.io/docs/specs/prw/remote_write_spec/) —
способ reliably передавать семплы из Prometheus/агента в долгосрочное хранилище
без потерь. Это **не** протокол «приложение → Prometheus» (это anti-pattern,
заложенный в спецификацию: «not intended for use by applications to push
metrics») — его отправитель это скрейпер (Prometheus, vmagent, Grafana Agent/Alloy).

| Аспект | Remote Write **1.0** | Remote Write **2.0** |
|---|---|---|
| Статус | Published (апрель 2023) | Experimental (rc, май 2024) |
| Транспорт | HTTP POST, protobuf, **snappy block-формат** | то же + `;proto=io.prometheus.write.v2.Request` в Content-Type |
| Сообщение | `prometheus.WriteRequest` (deprecated в 2.0) | `io.prometheus.write.v2.Request` |
| Что внутри | серии+лейблы+семплы | + **symbols (string interning)** — словарь строк для сжатия, + **metadata** (тип/help/unit), + **exemplars**, + **native histograms**, + `start_timestamp` (created timestamp) |
| Негоциация | заголовок `X-Prometheus-Remote-Write-Version: 0.1.0` | + обязательные ответные заголовки `X-Prometheus-Remote-Write-{Samples,Histograms,Exemplars}-Written` для подтверждения записи |
| Ретраи | MUST retry 5xx; MAY 429; MUST NOT 2xx/4xx (кроме 429) | то же + обработка partial write и 415 Unsupported Media Type |
| Порядок | семплы одной серии — строго по времени | то же; приоритет: min-in-order per series |

Все детали 1.0 — заголовки, семантика ретраев, stale markers (специальный NaN
`0x7ff0000000000002`), перечень совместимых sender/receiver — в
[спецификации 1.0](https://prometheus.io/docs/specs/prw/remote_write_spec/);
2.0 с обоснованием (rationale PR) — в
[спецификации 2.0](https://prometheus.io/docs/specs/prw/remote_write_spec_2_0/).
Кто принимает remote write: Prometheus, Mimir, Cortex, Thanos Receive,
VictoriaMetrics, OpenTelemetry Collector (receiver), Elastic Agent, Vector и др.
([список в спецификации](https://prometheus.io/docs/specs/prw/remote_write_spec/#compatible-senders-and-receivers)).

### 2.5 Service discovery и паттерн ServiceMonitor CRD

Prometheus сам не знает цели — цели приходят из **service discovery**:
`static_configs`, `file_sd`, `http_sd`, Kubernetes, Consul и др.
([HTTP SD](https://prometheus.io/docs/prometheus/latest/http_sd/)).
В Kubernetes deployment-паттерн смещается с «править prometheus.yml» на
**декларативные CRD** [Prometheus Operator](https://prometheus-operator.dev/):

- `ServiceMonitor` — «скрейпи Service с такими label-селекторами по таким портам»;
- `PodMonitor` — прямое опрашивание подов;
- `Probe` — blackbox-пробы; `PrometheusRule` — правила алертинга.

Helm-чарт [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
ставит весь набор разом. VictoriaMetrics-стек повторяет этот паттерн своими
CRD (`VMServiceScrape`, `VMPodScrape`, `VMRule` и т.д. —
[operator](https://docs.victoriametrics.com/operator/)). Смысл паттерна:
**приложение объявляет intent («у меня есть `/metrics` на порту X») лейблами,
а скрейп настраивается автоматически** — config-as-code из Git, без ручных
правок конфига мониторинга.

### 2.6 High-cardinality: главная ловушка метрик

В Prometheus-модели **каждая уникальная комбинация лейблов — отдельная
временная серия**, живущая в памяти инстанса
([data model](https://prometheus.io/docs/concepts/data_model/)). Отсюда правила:

- Никогда не лейблить идентификаторами неограниченной мощности: `user_id`,
  `request_id`, `trace_id`, `email`, URL с параметрами — это **взрыв серий**
  (cardinality explosion) и OOM TSDB. High-cardinality данные — работа логов и
  трейсов, а не метрик.
- Продумывай лейблы заранее: «лейблы с ограниченным набором значений»
  ([naming best practices](https://prometheus.io/docs/practices/naming/)).
- Инструменты контроля: `/api/v1/status/tsdb` в Prometheus, cardinality
  explorer в VictoriaMetrics ([vmui](https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/#cardinality-explorer)),
  лимитеры серий в Mimir/VM.
- Реверс: если всё же нужна per-request/per-user аналитика — это задача
  структурного хранилища (ClickHouse-подход, exemplars + трейсы), а не метрик.

---

## 3. 📝 Логи

### 3.1 Структурированные vs неструктурированные

| | Неструктурированные (plain text) | Структурированные (JSON) |
|---|---|---|
| Формат | свободный текст + парсеры (regex) | поля ключ-значение (JSON) |
| Стоимость разбора | парсинг на лету в агенте, хрупко | нулевой, поля уже есть |
| Фильтрация по полю | полнотекст/regex | нативная по полю |
| Стоимость человека | дёшево писать | чуть дороже писать, дешевле читать |
| Рекомендация | только для унаследованного | **дефолт для новых приложений** |

JSON-логи — минимальное обязательное условие полезного log-пайплайна: агенту
не нужно гадать парсером. В прошлом аудите homelab уже отмечено, что Traefik,
Immich, Vault, Stalwart включают JSON-логи переменными окружения (см.
[monitoring-systems-overview.md](monitoring-systems-overview.md) §7).

### 3.2 Уровни (severity)

Традиция Unix — syslog severity из [RFC 5424](https://datatracker.ietf.org/doc/html/rfc5424):
8 уровней 0–7 (emerg, alert, crit, err, warning, notice, info, debug).
Прикладные логгеры обычно используют 5–6 (trace/debug/info/warn/error/fatal).
OpenTelemetry нормализует всё это в числовое поле `SeverityNumber` —
[24 диапазона](https://opentelemetry.io/docs/specs/otel/logs/data-model/#field-severitynumber),
сгруппированных по 4: TRACE(1–4), DEBUG(5–8), INFO(9–12), WARN(13–16),
ERROR(17–20), FATAL(21–24); рядом хранится исходная строка `SeverityText`
(например, «Informational» из syslog), чтобы не терять детали источника.

### 3.3 Подходы к сбору

| Паттерн | Как работает | Плюсы | Минусы | Когда |
|---|---|---|---|---|
| **DaemonSet-агент на ноде** | один под на ноду читает stdout/stderr всех контейнеров (через containerd/файлы) | один агент на ноду, дешёво, автодискавери метаданных подов | общая конфигурация на всех подов ноды | **дефолт в k8s** (Promtail/Alloy/Fluent Bit/Vector) |
| **Sidecar-агент** | агент-контейнер в каждом поде | изоляция, per-app маршрутизация, file-логи | N× ресурсов, шум | когда логи пишутся в файлы внутри приложения или нужна строгая изоляция |
| **Центральный сборщик** | приложения/агенты шлют напрямую в collector-гateway (OTLP/Loki API) | единая точка обработки, сэмплинг, буферизация | ещё один hop | при OTel-first архитектуре, multi-cluster |
| **Push напрямую из приложения** | SDK пишет в backend | без агента | связность кода с бэкендом | редко; лучше через OTel SDK → collector |

Практика: **DaemonSet — дефолт; sidecar — исключение; центральный collector —
закономерная надстройка над DaemonSet'ом** (агенты на нодах → gateway-collector
→ бэкенды).

### 3.4 Хранение и индексация: три философии

| Подход | Как ищет | Стоимость индекса | Сильная сторона | Слабая сторона | Представители |
|---|---|---|---|---|---|
| **Полнотекстовый (inverted index)** | индексирует токены содержимого | большой и дорогой | произвольный поиск по любому слову | дорогие ресурсы, лицензионные нюансы | Elasticsearch/OpenSearch |
| **Label-based индекс** | индексируются только лейблы, контент сканируется при запросе | крошечный | дёшево хранить терабайты | медленный произвольный поиск по содержимому | Loki |
| **Колонко-ориентированное** | колонки = поля, эффективные сжатие/фильтры | умеренный, гибкий | SQL-скорость по структурированным логам, полнотекст тоже есть | требует структуру (JSON) | ClickHouse, VictoriaLogs, Quickwit |

Важные нюансы от первоисточников:

- **Loki** сознательно не индексирует содержимое строки: «the content of each
  log line is not indexed. Instead, log entries are grouped into streams which
  are indexed with labels» — и требует лейблы низкой кардинальности (10–15
  штук), иначе «Loki performs very poorly»
  ([Understand labels](https://grafana.com/docs/loki/latest/get-started/labels/)).
  Всё остальное (уровень, поля) — [structured metadata](https://grafana.com/docs/loki/latest/get-started/labels/structured-metadata/),
  а не индекс-лейблы. С 3.x Loki умеет принимать OTLP и сам маппит OTel
  resource-атрибуты в индекс-лейблы по умолчанию
  ([default OTel labels](https://grafana.com/docs/loki/latest/get-started/labels/#default-labels-for-opentelemetry)).
- **Elasticsearch/OpenSearch** строят инвертированный индекс по токенам —
  произвольный поиск быстрый, но индекс сопоставим по объёму с данными;
  OpenSearch — Apache-2.0 форк ES 7.10 с бесплатными SAML/OIDC (см.
  [monitoring-systems-overview.md](monitoring-systems-overview.md) §3).
- **VictoriaLogs** — «user-friendly cost-efficient database for logs» от
  команды VictoriaMetrics: колонко-ориентированный движок с битовыми индексами,
  полнотекстовый поиск по полям, LogsQL; принимает данные от Fluent Bit, Vector,
  Promtail, syslog, journald, OTel
  ([VictoriaLogs docs](https://docs.victoriametrics.com/victorialogs/),
  [data ingestion](https://docs.victoriametrics.com/victorialogs/data-ingestion/)).
- **ClickHouse-стеки** (SigNoz, qryn, HyperDX) используют колонко-ориентированную
  СУБД для логов+трейсов+метрик — скорость SQL-запросов по историческим данным
  (сравнение стеков: [monitoring-systems-overview.md](monitoring-systems-overview.md) §3).

### 3.5 Языки запросов — кратко

| Язык | Где | Идея |
|---|---|---|
| **LogQL** | Loki | selectors по лейблам `{job="nginx"} \|= "error" \| json \| level="warn"` + pipelines-операторы + метрики из логов `rate({...}[5m])` ([docs](https://grafana.com/docs/loki/latest/query/)) |
| **LogsQL** | VictoriaLogs | `error (service.name="api" OR service.name="web") \| stats by (level) count()` — фильтры по полям + SQL-подобные агрегации ([docs](https://docs.victoriametrics.com/victorialogs/logsql/)); есть конвертер LogQL→LogsQL ([docs](https://docs.victoriametrics.com/victorialogs/logql-to-logsql/)) |
| **Elasticsearch DSL** | ES/OpenSearch | JSON-запросы `bool/query/must/filter` + aggregation framework; на OpenSearch — ещё и SQL/PPL-синтаксис |
| **OTel Logs data model** | стандарт | не язык, а **схема записи**: Timestamp, ObservedTimestamp, TraceId/SpanId, SeverityNumber/Text, Body, Resource, InstrumentationScope, Attributes, EventName ([spec](https://opentelemetry.io/docs/specs/otel/logs/data-model/)) |

Модель данных OTel важна именно как **мирный договор**: любой источник
(syslog, journald, Apache-логи, JSON-логи приложения) маппится в неё без
потерь — приложение-агент (Fluent Bit, Vector, OTel Collector) может отдавать
логи в эту модель, и бэкенды (Loki OTLP-ingest, VictoriaLogs, Elasticsearch)
принимают их уже нормализованными ([data model requirements](https://opentelemetry.io/docs/specs/otel/logs/data-model/#design-notes)).

---

## 4. 🔍 Трейсинг

### 4.1 Span, trace, контекст

**Распределённый трейс** — это дерево span'ов, описывающих путь одного запроса
через систему. W3C определяет задачу так: «follow, analyze and debug a
transaction across multiple software components», где контекст должен
путешествовать между сервисами
([W3C Trace Context, problem statement](https://www.w3.org/TR/trace-context/#problem-statement)).

- **Span** — одна операция (HTTP-обработчик, SQL-запрос): имя, время старта/конца,
  атрибуты, статус, parent.
- **Trace** — всё дерево span'ов с общим `trace_id`.
- **Контекст-пропагация** — передача идентификаторов через границы сервисов.

### 4.2 W3C Trace Context: `traceparent` и `tracestate`

[W3C Trace Context](https://www.w3.org/TR/trace-context/) — W3C Recommendation
(23 ноября 2021), стандарт пропагации по HTTP:

- Заголовок **`traceparent`** — фиксированный формат:
  `00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01` =
  `version-trace_id-parent_id-trace_flags`:
  - `trace_id` — 16 байт hex (уникальный ID всего трейса; нулевой запрещён);
  - `parent_id` — 8 байт hex (ID span'а вызывающего);
  - `trace_flags` — 8 бит; сегодня определён только младший бит `sampled`
    ([спецификация §3.2](https://www.w3.org/TR/trace-context/#traceparent-header)).
- Заголовок **`tracestate`** — опциональный список `key=value` пар (до 32
  вендор-специфичных записей) для передачи данных конкретных трейс-систем;
  левая позиция — самый свежий контекст
  ([§3.3](https://www.w3.org/TR/trace-context/#tracestate-header)).
- Правила мутаций: сервис обязан обновлять `parent_id`, обязан пробрасывать
  заголовок даже если не трейсит сам (pass-through), может «перезапустить»
  трейс на границе доверенного периметра
  ([§3.4](https://www.w3.org/TR/trace-context/#mutating-the-traceparent-field)).

**W3C Baggage** — отдельная W3C-спецификация для проброса произвольных
key-value пар бизнес-контекста (tenant id, feature flag) через всё
приложение; OTel SDK поддерживает её как примитив `Baggage`
([W3C Baggage](https://www.w3.org/TR/baggage/)). Важно: baggage — это
**данные**, а не трейс-идентификация; в security-чувствительных случаях их
надо фильтровать на границе.

**B3 propagation** — исторический формат Zipkin (заголовки `b3`,
`X-B3-TraceId`, `X-B3-SpanId`, `X-B3-Sampled`, `X-B3-Flags`); до сих пор
широко поддержан и конвертируется OTel-пропагаторами
([openzipkin/b3-propagation](https://github.com/openzipkin/b3-propagation)).

### 4.3 Sampling: head-based vs tail-based

Трейсить всё — слишком дорого, поэтому вводят сэмплинг. Два семейства:

| | Head-based | Tail-based |
|---|---|---|
| Решение принимается | в начале трейса (в корневом сервисе) | в конце, на сборщике, видевшим весь трейс |
| Флаг `sampled` из W3C | определяется сразу и пробрасывается | решение отложено (delayed/deferred — сценарии прямо упомянуты в [W3C spec §3.2.2.5.1](https://www.w3.org/TR/trace-context/#sampled-flag)) |
| Плюс | дёшево, предсказуемая нагрузка | можно оставить **все ошибочные/медленные** трейсы + процент обычных |
| Минус | теряются «интересные» трейсы, о которых узнали позже | коллектор держит все трейсы в памяти/буфере |
| Где реализовано | SDK OTel (`TraceIdRatioBased`, parent-based) | OTel Collector [tail_sampling processor](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/tailsamplingprocessor); Tempo TraceQL-фильтры при приёме |

Канонический подход OTel описан в
[docs/concepts/sampling](https://opentelemetry.io/docs/concepts/sampling/):
head sampling — дефолт в SDK, tail sampling — задача коллектора. Практический
рецепт: head-based ratio 1–10% + tail-based политика «всё с error / latency > N /
100% для trace_id из канарейки».

### 4.4 История: OpenTracing + OpenCensus → OpenTelemetry

- **OpenTracing** (2016, CNCF) — vendor-neutral API трейсинга (Jaeger-мир).
- **OpenCensus** (2018, Google) — альтернативный API + метрики + трейсы.
- В мае 2019 оба проекта объявили о слиянии в **OpenTelemetry** под эгидой CNCF
  — единые API, SDK, протокол и semantic conventions для всех сигналов
  ([история на opentelemetry.io](https://opentelemetry.io/docs/what-is-opentelemetry/)).
- Сегодня OpenTelemetry — второй по активности проект CNCF после Kubernetes,
  а Jaeger и Zipkin признают OTel-модель данных родной (Jaeger v2 построен на
  фреймворке OTel Collector — [jaegertracing.io](https://www.jaegertracing.io/docs/latest/)).

### 4.5 Бэкенды трейсинга — кратко

Формат приёма важнее, чем UI: важно, чтобы бэкенд принимал **OTLP** — тогда
инструментирование не привязано к вендору.

| Бэкенд | Принимает | Хранилище | Примечание |
|---|---|---|---|
| **Jaeger v2** | OTLP, Jaeger thrift/binary, Zipkin | ES/OpenSearch, Cassandra, ClickHouse, Badger | CNCF graduated; v2 = OTel Collector под капотом ([docs](https://www.jaegertracing.io/docs/latest/)) |
| **Grafana Tempo** | OTLP, Jaeger, Zipkin | **только object storage (S3 и совместимые)** | дёшево на больших объёмах; TraceQL; metric-generator для связки с метриками ([docs](https://grafana.com/docs/tempo/latest/)) |
| **Zipkin** | Zipkin JSON/thrift (+ мосты) | in-memory, ES, Cassandra, MySQL | легаси-стандарт, редко выбирают новым ([zipkin.io](https://zipkin.io/)) |
| **VictoriaTraces** | OTLP | свой движок | молодой продукт от VictoriaMetrics ([docs](https://docs.victoriametrics.com/victoriatraces/)) |
| Коммерческие (Datadog APM, New Relic, Dynatrace) | OTLP, собственные агенты | SaaS | все крупные вендоры уже принимают OTLP ([OTel registry](https://opentelemetry.io/ecosystem/vendors/)) |

---

## 5. ☁️ OpenTelemetry как стандарт-зонтик

OpenTelemetry — CNCF-проект, объединяющий **API, SDK, протокол (OTLP),
semantic conventions и коллектор** для всех сигналов. Это не «очередной
продукт мониторинга», а набор стандартов, позволяющих инструментировать
приложение один раз и менять бэкенд без изменения кода.

### 5.1 OTLP: OpenTelemetry Protocol

[OTLP 1.11.0](https://opentelemetry.io/docs/specs/otlp/) — request/response
протокол доставки телеметрии. Статус сигналов: **traces, metrics, logs —
Stable; profiles — Development**
([spec header](https://opentelemetry.io/docs/specs/otlp/)).

| Транспорт | Порт | Путь | Кодирование |
|---|---|---|---|
| **OTLP/gRPC** | **4317** | gRPC-сервис `opentelemetry.proto.collector.*` | binary protobuf |
| **OTLP/HTTP (protobuf)** | **4318** | `/v1/traces`, `/v1/metrics`, `/v1/logs`, `/v1development/profiles` | binary protobuf (`application/x-protobuf`) |
| **OTLP/HTTP (JSON)** | 4318 | те же пути | protobuf-JSON-маппинг (`application/json`), enum-значения — числами, `traceId`/`spanId` — hex-строками |

Ключевые семантики из спецификации:

- **Partial success**: сервер частично принял данные → отвечает 200 с полем
  `partial_success` и счётчиками `rejected_spans/rejected_data_points/rejected_log_records`;
  клиент **не должен** ретраить такой запрос.
- **Retry-семантика**: gRPC-коды UNAVAILABLE/DEADLINE_EXCEEDED/CANCELLED и
  HTTP 429/502/503/504 — ретраебельны; INVALID_ARGUMENT и 400 — нет; при
  перегрузке сервер сигнализирует backpressure (RetryInfo / Retry-After).
- **Мульти-дестинейшн**: клиент, шлющий в несколько бэкендов, ведёт отдельные
  очереди/ретраи на каждый destination, чтобы быстрый бэкенд не ждал медленный
  ([Multi-Destination Exporting](https://opentelemetry.io/docs/specs/otlp/#multi-destination-exporting)).
- Размер сообщения: рекомендация 64 MiB на запрос, 4 MiB на ответ; компрессия
  gzip/none обязательна к поддержке сервером.
- Версионирование без номеров версий: эволюция через добавление опциональных
  полей protobuf; старые клиенты/серверы обязаны оставаться совместимыми
  ([Future Versions and Interoperability](https://opentelemetry.io/docs/specs/otlp/#future-versions-and-interoperability)).

SDK-конфигурация стандартизирована через переменные окружения — это то, что
делает OTLP переносимым на практике:
`OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_PROTOCOL`
(`grpc` | `http/protobuf` | `http/json`), `OTEL_EXPORTER_OTLP_HEADERS`,
`OTEL_EXPORTER_OTLP_TIMEOUT`, `OTEL_SERVICE_NAME`, `OTEL_RESOURCE_ATTRIBUTES`
([OTLP exporter configuration](https://opentelemetry.io/docs/languages/sdk-configuration/otlp-exporter/)).

### 5.2 Архитектура: SDK → Collector → бэкенд

Каноническая цепочка:

```
приложение (OTel SDK или нулевая инструментировка)
      │  OTLP (4317/4318)
      ▼
OTel Collector — agent (DaemonSet/sidecar на ноде)
      │  OTLP
      ▼
OTel Collector — gateway (центральный сервис, опционально)
      │  remote_write / OTLP / Loki API / любой exporter
      ▼
бэкенды: Prometheus/VictoriaMetrics/Mimir · Loki/VictoriaLogs/ES · Tempo/Jaeger
```

Два паттерна развёртывания коллектора документированы официально:

- **Agent** — демон на той же машине/ноде, принимает данные от библиотек
  локально (низкая задержка, нет сетевых отказов между приложением и агентом).
- **Gateway** — отдельный сервис, принимает от многих агентов: центральная
  точка для tail-sampling, тегирования, маршрутизации между арендаторами
  ([Collector architecture: agent vs gateway](https://opentelemetry.io/docs/collector/architecture/)).

Промежуточный вариант — **sidecar** (агент-контейнер в поде), упомянутый там же.

### 5.3 Semantic conventions, Resource, Instrumentation Scope

- **Resource** — неизменяемое описание источника телеметрии: кто и где её
  произвёл (service.name, service.version, k8s.pod.name, cloud.region…).
  Прикрепляется ко **всем** сигналам от этого источника — потому resource —
  главный «клей» корреляции.
- **Instrumentation Scope** — описывает, какой именно библиотекой/модулем внутри
  источника сгенерированы данные (name, version) — позволяет различать
  инструментирование от разных библиотек в одном процессе.
- **Semantic conventions** — словарь стандартных имён атрибутов (HTTP-запросы,
  БД, messaging, k8s…): `http.request.method`, `db.system.name`,
  `k8s.namespace.name` и т.д. ([semconv](https://opentelemetry.io/docs/specs/semconv/)).
  Именно они превращают «просто поля» в запросимые факты и унифицируют
  дашборды между языками.

Как бэкенды справляются с resource-атрибутами (важно для cardinality):
Prometheus по умолчанию **не** продвигает resource-атрибуты в лейблы — вместо
этого кладёт их в служебную метрику `target_info`, а продвигаемый список
настраивается через `otlp.promote_resource_attributes`
([Prometheus OTLP guide](https://prometheus.io/docs/guides/opentelemetry/)).
VictoriaMetrics по умолчанию, наоборот, продвигает все resource-атрибуты в
лейблы, с флагами `-opentelemetry.promoteResourceAttributes` для выборочного
режима ([VM OTLP integration](https://docs.victoriametrics.com/victoriametrics/integrations/opentelemetry/)).

### 5.4 Collector: receivers, processors, exporters, connectors

Коллектор — конвейеры (pipelines) по типу сигнала: `traces`, `metrics`, `logs`;
в пайплайне receivers → processors → exporters, данные из одного receiver
fan-out'ятся во все exporters пайплайна
([architecture](https://opentelemetry.io/docs/collector/architecture/)).

| Компонент | Роль | Примеры |
|---|---|---|
| **Receiver** | приём (pull или push) | `otlp`, `prometheus` (скрейпер), `zipkin`, `jaeger`, `filelog`, `k8sevents` |
| **Processor** | трансформация/фильтрация/сэмплинг/батчинг | `batch`, `memory_limiter`, `attributes`, `transform`, `filter`, `probabilisticsampler`, `tail_sampling`, `k8sattributes` (обогащение под-метаданными) |
| **Exporter** | отправка наружу | `otlp`, `prometheusremotewrite`, `loki`, `kafka`, `debug` |
| **Connector** | соединяет два пайплайна: «выход одного = вход другого», часто конвертируя сигнал | `spanmetrics` (traces→metrics), `deltatocumulative`, `count` |
| **Extension** | вспомогательное (health_check, pprof, auth) | — |

Практический рецепт связки сигналов именно на коллекторе: **spanmetrics
connector** — из трейсов строит RED-метрики (`duration`, `calls`) с теми же
лейблами сервиса, что и трейсы, → они попадают в Prometheus/VM и даются
в exemplars; **k8sattributes processor** — обогащает все сигналы pod/namespace
метаданными до того, как они уйдут в бэкенд.

### 5.5 Зрелость сигналов и статус поддержки

| Сигнал | Статус в OTLP | Комментарий |
|---|---|---|
| Traces | **Stable** | с 2021, самый зрелый |
| Metrics | **Stable** | включая exponential histograms |
| Logs | **Stable** | data model stable, приём в бэкендах повсеместный |
| Profiles | **Development / Alpha** | формат на базе pprof protobuf, `pprof`-superset, привязка к trace/span через `Link` ([profiles spec](https://opentelemetry.io/docs/specs/otel/profiles/)) |

Статус приёма OTLP у основных бэкендов:

| Бэкенд | Принимает OTLP? | Особенности |
|---|---|---|
| Prometheus | ✅ метрики, флагом `--web.enable-otlp-receiver`, путь `/api/v1/otlp/v1/metrics` | только OTLP/HTTP; delta→cumulative — экспериментально ([guide](https://prometheus.io/docs/guides/opentelemetry/)) |
| Mimir | ✅ метрики (+ трейсы не хранит) | via OTel exporter ([docs](https://grafana.com/docs/mimir/latest/)) |
| Grafana Loki | ✅ логи, нативный OTLP-приём | сам маппит OTel resource-атрибуты в лейблы/structured metadata ([docs](https://grafana.com/docs/loki/latest/get-started/labels/#default-labels-for-opentelemetry)) |
| Grafana Tempo | ✅ трейсы | OTLP gRPC+HTTP как основной современный канал ([docs](https://grafana.com/docs/tempo/latest/)) |
| VictoriaMetrics | ✅ метрики, `/opentelemetry/v1/metrics` | protobuf+gzip; exponential histograms конвертируются; delta-временность сохраняется as-is с v1.132 ([docs](https://docs.victoriametrics.com/victoriametrics/integrations/opentelemetry/)) |
| VictoriaLogs | ✅ логи | OTLP ingestion ([docs](https://docs.victoriametrics.com/victorialogs/data-ingestion/opentelemetry/)) |
| Jaeger v2 | ✅ трейсы | коллектор-фреймворк — OTLP нативен ([jaegertracing.io](https://www.jaegertracing.io/docs/latest/)) |
| Elasticsearch/OpenSearch | ⚠️ через интеграции/агенты (Elastic Agent, Data Prepper) | не нативный OTLP-endpoint в OSS-движке |
| Grafana Alloy | ✅ «vendor-neutral дистрибуция OTel Collector» | единый агент для всех сигналов ([docs](https://grafana.com/docs/alloy/latest/)) |

---

## 6. 🔗 Может ли оно всё работать вместе?

Короткий ответ: **да, и именно так обычно и строят** — по трём типовым
архитектурам.

### 6.1 «Классический» стек: Prometheus + Loki + Tempo + Grafana (LGTM)

```
приложения ──/metrics──▶ Prometheus ─┐
   │                                 ├──▶ Grafana (единый UI)
   ├──OTLP──▶ Alloy ─┬─ Loki (логи) ─┘
   │                 ├─ Tempo (трейсы)
   │                 └─ Prometheus (метрики из скрейпа/OTLP)
```

Корреляция внутри этого стека — эталон для остальных:

- **Exemplars в Grafana**: Prometheus-гистограмма с exemplars (`trace_id`) →
  клик по точке → трейс в Tempo
  ([Grafana exemplars](https://grafana.com/docs/grafana/latest/fundamentals/exemplars/)).
- **Derived fields в Loki datasource**: из поля `trace_id` в логе генерируется
  ссылка на Tempo-трейс — из строки лога прыгаешь в трейс одним кликом
  ([configure Loki data source: derived fields](https://grafana.com/docs/grafana/latest/datasources/loki/configure-loki-data-source/#derived-fields)).
- **Trace-to-logs / trace-to-metrics в Tempo datasource**: из span'а — к логам
  этого запроса в Loki и к метрикам в Prometheus/VM
  ([Tempo datasource](https://grafana.com/docs/grafana/latest/datasources/tempo/)).
- Условие работоспособности: **W3C trace_id должен быть в логах** (OTel SDK в
  приложениях) и **exemplars должны включаться** в клиентских библиотеках
  Prometheus/OpenMetrics.

### 6.2 VictoriaMetrics стек: vmagent + VictoriaMetrics + VictoriaLogs + vmalert

Та же топология, другой набор продуктов (Apache-2.0, меньше ресурсов — детали
выбора в [monitoring-systems-overview.md](monitoring-systems-overview.md) §2.3):

```
exporters ──pull──▶ vmagent ──remote_write──▶ VictoriaMetrics ◀──OTLP── Alloy/OTel Collector
                                                  │
                                    vmalert ──▶ Alertmanager
Логи: Fluent Bit/Vector/Alloy ──▶ VictoriaLogs (LogsQL)
Трейсы: OTLP ──▶ VictoriaTraces или Jaeger
UI: Grafana (VM + VictoriaLogs + traces datasources)
```

- VictoriaMetrics принимает **и** remote write (1.0 и 2.0), **и** OTLP-метрики,
  **и** Influx/Graphite/OpenTSDB/Datadog/Zabbix-коннектор — это делает её
  «толстым хабом» для метрик из гетерогенных источников
  ([список протоколов](https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/#prominent-features)).
- При OTLP-приёме VictoriaMetrics умеет конвертировать имена в
  Prometheus-совместимые (`-opentelemetry.usePrometheusNaming`), конвертирует
  exponential histograms в `vmrange`-бакеты, рекомендует cumulative-временность
  ([VM OTLP](https://docs.victoriametrics.com/victoriametrics/integrations/opentelemetry/)).
- Correlation-механики Grafana (exemplars/derived fields) работают так же,
  т.к. datasource'ы стандартные.

### 6.3 «Всё в одном» через OTel Collector

Полностью vendor-neutral вариант: **один коллектор принимает всё по OTLP и
маршрутизирует куда нужно**:

```
 OTel SDK приложений (все сигналы)
        │ OTLP
        ▼
 OTel Collector (agent DaemonSet)
        │ OTLP
        ▼
 OTel Collector (gateway) ──fan-out──▶ VictoriaMetrics   (remote_write)
        │        ├──────────────────────▶ Loki/VictoriaLogs (OTLP/Loki API)
        │        ├──────────────────────▶ Tempo/Jaeger      (OTLP)
        │        └──────────────────────▶ Elasticsearch     (elasticsearch exporter)
```

Преимущества: смена бэкенда = правка exporter'а в конфиге коллектора; tail-sampling
и обогащение — в одном месте; multi-tenancy маршрутизация. Цена: ещё одна служба в эксплуатации (собственные очереди/буферы/HA коллектора). OTLP прямо
документирует multi-destination fan-out как штатный сценарий
([спецификация](https://opentelemetry.io/docs/specs/otlp/#multi-destination-exporting)).

### 6.4 Единство через Grafana

Grafana — не хранилище, а «универсальный пульт»: datasource'ы к Prometheus/VM,
Loki/VictoriaLogs, Tempo/Jaeger/Elasticsearch + **Grafana Unified Alerting**
поверх всех источников (alert rules могут объединять данные разных датасорсов,
единые contact points и silence'ы —
[unified alerting](https://grafana.com/docs/grafana/latest/alerting/)).
Плюс provisioning дашбордов и datasource'ов как код
([provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/)).
Для homelab это означает: хранилища можно менять поодиночке, UI — один.

### 6.5 Таблица совместимости: кто какой протокол принимает

| Источник → Бэкенд | remote_write | OTLP | Loki API (`/loki/api/v1/push`) | Elasticsearch API | Zipkin/Jaeger форматы |
|---|---|---|---|---|---|
| **Prometheus** | ✅ sender | ✅ sender (метрики) | ❌ | ❌ | ❌ |
| **OTel Collector / Alloy** | ✅ (exporter) | ✅ | ✅ | ✅ | ✅ |
| **VictoriaMetrics** | ✅ receiver | ✅ (метрики) | ❌ | ❌ (import-эндпоинты — отдельный формат) | ❌ (трейсы — VictoriaTraces) |
| **VictoriaLogs** | ❌ | ✅ (логи) | ⚠️ [Promtail-режим](https://docs.victoriametrics.com/victorialogs/data-ingestion/promtail/); ES-совместимый ingestion API ([docs](https://docs.victoriametrics.com/victorialogs/data-ingestion/)) | ⚠️ совместимый `_bulk`-приём | ❌ |
| **Loki** | ❌ | ✅ (логи) | ✅ (нативный) | ❌ | ❌ |
| **Prometheus/Mimir** | ✅ receiver (Mimir) | ✅ (Mimir) | ❌ | ❌ | ❌ |
| **Tempo** | ❌ | ✅ | ❌ | ❌ | ✅ Jaeger/Zipkin приём |
| **Jaeger v2** | ❌ | ✅ | ❌ | ❌ | ✅ Jaeger/Zipkin приём |
| **Elasticsearch/OpenSearch** | ❌ | ⚠️ через агенты | ❌ | ✅ (нативный) | ❌ |
| **Vector / Fluent Bit** | ✅ (Vector sink) | ✅ | ✅ | ✅ | — |

Практический вывод из таблицы: **OTLP и Prometheus remote_write — два
«универсальных адаптера»**. Всё, что умеет принимать OTLP + remote_write,
совместимо почти с любым агентом. Elasticsearch API и Loki API — нишевые
интерфейсы со своими экосистемами.

---

## 7. ☸️ Kubernetes-специфика (актуально: k0s)

### 7.1 Метрики кластера: кто и что экспортирует

| Компонент | Что даёт | Как разворачивается |
|---|---|---|
| [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics) | состояние объектов API (deployments, pods, nodes, PVC…) как метрик | Deployment + Service; скрейпится через ServiceMonitor |
| [node-exporter](https://github.com/prometheus/node_exporter) | хостовые метрики ноды (CPU, RAM, disk, net) | **DaemonSet** + hostNetwork/hostPID |
| cAdvisor (встроен в kubelet) | метрики контейнеров/подов | kubelet отдаёт сам на `/metrics/cadvisor`; скрейпит Prometheus с ролью node |
| metrics-server | API Metrics для HPA/kubectl top | отдельный компонент, не для мониторинга, а для autoscaling ([docs](https://github.com/kubernetes-sigs/metrics-server)) |
| kubelet `/metrics` | сам kubelet (runtime, volumes и пр.) | скрейп по всем нодам |

### 7.2 kube-prometheus-stack vs victoria-metrics-k8s-stack

Оба стека решают одну задачу — «весь мониторинг кластера из Helm-чарта», разница
в хранилище и CRD-механике (детальное сравнение —
[monitoring-systems-overview.md](monitoring-systems-overview.md) §5):

| | kube-prometheus-stack | victoria-metrics-k8s-stack |
|---|---|---|
| Хранилище метрик | Prometheus (+ Thanos/Mimir/remote_write) | VictoriaMetrics single/cluster |
| CRD скрейпа | ServiceMonitor/PodMonitor/Probe ([prometheus-operator.dev](https://prometheus-operator.dev/)) | VMServiceScrape/VMPodScrape/VMProbe ([operator](https://docs.victoriametrics.com/operator/)) |
| Алертинг | Prometheus rules → Alertmanager | vmalert → Alertmanager |
| Готовые дашборды | ✅ огромное сообщество | ✅ поставляются в чарте |
| Ресурсы | выше | ниже (заявлено; vendor benchmark) |

### 7.3 Сбор логов: DaemonSet-агенты

| Агент | Язык/ресурсы | Принимает | Особенности |
|---|---|---|---|
| [Grafana Alloy](https://grafana.com/docs/alloy/latest/) | Go | всё (Prometheus-скрейп, OTLP, docker-логи, файлы) | «vendor-neutral дистрибуция OTel Collector»; River-конфиг; дефолт Grafana-чартов |
| [Promtail](https://grafana.com/docs/loki/latest/send-data/promtail/) | Go | файлы/docker → Loki | **deprecated** в пользу Alloy |
| [Fluent Bit](https://docs.fluentbit.io/manual/) | C, очень лёгкий | tail, systemd, k8s | сотни input/output-плагинов; много выходов одновременно |
| [Vector](https://vector.dev/docs/) | Rust | файлы, docker, syslog, kafka | VRL-язык трансформаций; topologies: agent (DaemonSet) / aggregator / source |
| [fluentd](https://docs.fluentd.org/) | Ruby | классика | тяжелее Fluent Bit, экосистема плагинов |

Рекомендуемая связка для k0s: **один DaemonSet-агент на ноду → OTLP/remote_write
в бэкенды**; если OTel-first — Alloy или OTel Collector; если Loki-only —
Fluent Bit (лёгкий и многоцелевой). Метаданные подов (namespace, labels)
агент получает из k8s API — потому важно сразу закладывать resource-атрибуты
в модель.

### 7.4 Автоинструментирование приложений

Свои приложения не хочется инструментировать руками — OTel для этого даёт
**дистрибуции с автоинструментированием**:

- **Java/Node.js/Python**: agent/initializer — один sidecar/инициализатор с
  переменными `OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT` — и трейсы/метрики
  идут сами ([zero-code instrumentation](https://opentelemetry.io/docs/concepts/instrumentation/zero-code/)).
- **Go**: пока без полноценного auto-instrumentation агента (eBPF-подход в
  разработке; чаще явное SDK-инструментирование или eBPF-агенты вроде
  Grafana Beyla).
- **eBPF-подход**: Beyla (Grafana) / Coroot — инструментируют трафик на уровне
  ядра без изменения приложений — хороший вариант для чужих/унаследованных
  образов.

Паттерн для homelab: sidecar `OTEL_SERVICE_NAME=app` + `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317`
— минимальная связность кода с телеметрией, всё остальное решает коллектор.

---

## 8. 🏠 Вывод для этого homelab

Детальный план внедрения — в
[monitoring-systems-overview.md](monitoring-systems-overview.md) (§8, этапы 1–3).
Здесь — только **выбор стандартов**, чтобы не запереться в вендоре:

1. **Метрики — формат Prometheus (OpenMetrics) как язык данных** и
   **remote_write как транспорт** в долгосрочное хранилище (VictoriaMetrics).
   Remote Write 2.0 пока experimental — включать 1.0, следить за 2.0.
2. **Транспорт всех сигналов — OTLP** (стабилен для traces/metrics/logs).
   Приложения (свои Go/Node/Python) инструментировать через OTel SDK с
   `OTEL_EXPORTER_OTLP_ENDPOINT` на центральный collector/Alloy — тогда замена
   Loki↔VictoriaLogs или Tempo↔Jaeger не трогает приложения.
3. **Логи — структурированные (JSON) с уровнем и `trace_id` в каждом запросе**;
   OTel logs data model как целевая схема; severity нормализовать в
   SeverityNumber. Хранилище (Loki vs VictoriaLogs vs ES) — вопрос стоимости,
   не стандарта.
4. **Трейсы — W3C Trace Context как обязательная пропагация** (не B3-only),
   head-sampling в SDK + tail-sampling в коллекторе по мере роста объёма.
5. **Корреляция — сразу проектировать**: exemplars в гистограммах, derived
   fields Loki→Tempo (или эквивалент в Grafana для VictoriaLogs/VictoriaTraces),
   spanmetrics-коннектор. Это дешевле включить сразу, чем ретроактивно.
6. **Кластер (k0s)**: kube-prometheus-stack или victoria-metrics-k8s-stack —
   паттерн ServiceMonitor-подобных CRD и DaemonSet-агентов логов; свои
   приложения объявляют intent лейблами, мониторинг подхватывает сам
   (см. §7.2).
7. **Единственный вендор-лок в этой схеме — Grafana как UI**, и это осознанный
   компромисс: все данные лежат в open-форматах в self-hosted бэкендах,
   datasource'ы стандартные, и при необходимости UI заменяется (Perses,
   vmui, встроенные UI бэкендов) без миграции данных.
