# Мониторинг систем: анатомия, стеки и встраивание в homelab

Дата проверки: 2026-08-21. Все факты сверены с первоисточниками (официальные
документации, GitHub-репозитории, спецификации); версии зафиксированы через
GitHub Releases API на дату проверки. Живые проверки эндпоинтов выполнены на
сервере read-only через `ssh homelab-agent`.

## Вывод

Мониторинг — это не один продукт, а конвейер из компонентов: **инструментирование → сбор → транспорт → хранение (TSDB) → визуализация → алертинг → маршрутизация уведомлений**. Лучшие в классе self-hosted решения:

- 🥇 **Сбор метрик**: Prometheus или vmagent (VictoriaMetrics);
- 🥇 **Хранение**: VictoriaMetrics single-node (минимум RAM, официальный compose) или Mimir/Thanos для масштаба;
- 🥇 **Визуализация**: Grafana (де-факто стандарт, нативный OIDC);
- 🥇 **Алертинг**: Alertmanager или vmalert; уведомления — Telegram/webhook;
- 🥇 **Логи**: Loki или VictoriaLogs; **трейсинг**: Tempo/Jaeger;
- 🥇 **Пайплайн**: Grafana Alloy / OpenTelemetry Collector;
- 🏆 **Классика «всё в одном»**: Zabbix (SAML, но без OIDC), Netdata (реалтайм, но SSO только через облако).

Для этого homelab слой availability уже закрыт (Uptime Kuma + Gatus + Beszel).
Отсутствует слой **метрик приложений** в формате Prometheus. Рекомендуемый путь:

1. **Сейчас (Compose)**: добавить VictoriaMetrics (+vmagent/vmalert) + Grafana + postgres_exporter/redis_exporter/mysqld_exporter — один compose-файл покрывает ~20 контейнеров БД/кэша сразу.
2. **Потом**: включить нативные `/metrics` у 15+ своих приложений (см. §7 — большинство требуют одной переменной окружения).
3. **При переходе на k3s**: kube-prometheus-stack или victoria-metrics-k8s-stack — паттерн ServiceMonitor CRD вместо ручных scrape-конфигов.
4. **SSO**: Grafana — единая точка входа через generic OAuth/OIDC (Authentik/Pocket-ID/Zitadel подходят); Prometheus/Alertmanager/VictoriaMetrics сами OIDC не умеют — их за oauth2-proxy или vmauth. Gatus и Beszel уже поддерживают OIDC нативно.

---

## 1. 🧩 Из чего состоит система мониторинга

Каноническая модель описана самим проектом Prometheus:
[instrumented jobs → scraping → локальная TSDB → rules → Alertmanager → Grafana](https://prometheus.io/docs/introduction/overview/).

| Слой | Назначение | Примеры | Emoji |
|---|---|---|---|
| Инструментирование | Экспорт метрик из приложения | клиентские библиотеки, exporters ([каталог](https://prometheus.io/docs/instrumenting/exporters/)) | 🔌 |
| Сбор | Pull/push опрос целей, service discovery | Prometheus, vmagent, OTel Collector | 📡 |
| Транспорт | Формат передачи | exposition format (HTTP), [remote write 1.0/2.0](https://prometheus.io/docs/specs/prw/remote_write_spec/), OTLP | 🚚 |
| Хранение | TSDB, retention, даунсэмплинг | локальный TSDB, VictoriaMetrics, Mimir, Thanos | 🗄️ |
| Визуализация | Дашборды, explore | Grafana, встроенный vmui | 📈 |
| Алертинг | Правила на данных | alerting rules, vmalert, Grafana Alerting | 🚨 |
| Маршрутизация | Группировка, тишина, ингибиция, каналы | [Alertmanager](https://prometheus.io/docs/alerting/latest/overview/) | 📬 |
| On-call/инциденты | Дежурства, эскалации | PagerDuty, Grafana IRM, webhooks | 👮 |

### Ключевые концепции

- **Pull vs push.** Prometheus тянет по HTTP: легко поднять второй инстанс,
  видно, жива ли цель ([FAQ](https://prometheus.io/docs/introduction/faq/#why-do-you-pull-rather-than-push)).
  Push — только через шлюзы: [Pushgateway](https://prometheus.io/docs/practices/pushing/)
  рекомендован исключительно для результатов batch-задач (бэкапы!),
  т.к. помнит серии, пока их не удалишь вручную.
- **Три столпа и корреляция.** Метрики (Prometheus), логи («не храните их в
  Prometheus — берите Loki/OpenSearch», [FAQ](https://prometheus.io/docs/introduction/faq/)),
  трейсы (Tempo/Jaeger). Связки: exemplars позволяют из графика прыгнуть в трейс
  ([Tempo docs](https://grafana.com/docs/tempo/latest/)); `trace_id` в логах —
  как structured metadata Loki 3.0+, а не лейбл ([Loki FAQ](https://grafana.com/docs/loki/latest/)).
- **Service discovery.** Цели — из статики, `file_sd`, `http_sd`, Kubernetes,
  Consul ([HTTP SD](https://prometheus.io/docs/prometheus/latest/http_sd/)).
- **HA.** Prometheus — запускать дубликаты с дедупликацией выше по стеку;
  Alertmanager — gossip-кластер из 2–3 инстансов, fail-open
  ([HA doc](https://prometheus.io/docs/alerting/latest/high_availability/)).
- **Cardinality.** Каждая уникальная комбинация лейблов = новая серия;
  неограниченные лейблы (ID, trace_id) взрывают память
  ([data model](https://prometheus.io/docs/concepts/data_model/)).

---

## 2. 🏛️ Ядро: best-in-class open-source стеки

### 2.1 Экосистема Prometheus (Apache-2.0)

[Prometheus v3.14.0](https://github.com/prometheus/prometheus/releases/tag/v3.14.0) —
одиночный Go-бинарь, PromQL, десятки миллионов активных серий на инстанс.
Вокруг него: [node_exporter v1.12.1](https://github.com/prometheus/node_exporter/releases/tag/v1.12.1)
(хост), [cAdvisor v0.60.5](https://github.com/google/cadvisor/releases/tag/v0.60.5)
(контейнеры), [blackbox_exporter v0.28.0](https://github.com/prometheus/blackbox_exporter/releases/tag/v0.28.0)
(HTTP/TCP/ICMP/DNS-пробы — функциональный аналог части Gatus-проверок),
[kube-state-metrics v2.20.0](https://github.com/kubernetes/kube-state-metrics/releases/tag/v2.20.0),
[Alertmanager v0.34.0](https://github.com/prometheus/alertmanager/releases/tag/v0.34.0).

- **Kubernetes**: [Prometheus Operator](https://prometheus-operator.dev/) (v0.93.1)
  с CRD `ServiceMonitor`/`PodMonitor`/`Probe`; чарт
  [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
  ставит всё разом с готовыми дашбордами.
- **Compose**: официальных «батарейных» compose-стеков проект не публикует —
  собирается руками ([installation](https://prometheus.io/docs/prometheus/latest/installation/)).
- **Аутентификация**: только TLS + basic auth; «не доверенным пользователям не
  давайте HTTP-доступ» — [security model](https://prometheus.io/docs/operating/security/).
  OIDC/SAML/LDAP нет ни у Prometheus, ни у Alertmanager, ни у Pushgateway →
  впереди нужен oauth2-proxy/forward-auth.

### 2.2 Стек LGTM (Grafana Labs, AGPLv3)

- **Loki v3.7.6** — индексируются только лейблы, контент лежит сжатыми чанками
  в объектном хранилище → дёшево ([docs](https://grafana.com/docs/loki/latest/)).
  LogQL. Monolithic-режим хорош до ~20 GB/день
  ([deployment modes](https://grafana.com/docs/loki/latest/get-started/deployment-modes/));
  simple-scalable устарел и будет удалён в Loki 4.0.
- **Tempo v3.0.3** — трейсинг, хранение только в объектном хранилище, TraceQL,
  приём Jaeger/Zipkin/OTLP ([docs](https://grafana.com/docs/tempo/latest/)).
- **Mimir mimir-3.2.0** — горизонтально масштабируемое long-term хранилище
  метрик: принимает remote_write от Prometheus и OTLP от Alloy/Collector
  ([docs](https://grafana.com/docs/mimir/latest/)).
- **Grafana v13.2.0** — единый UI над всеми datasource'ами, unified alerting
  поверх нескольких источников, provisioning дашбордов как код
  ([provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/)).
- **Alloy** — «vendor-neutral дистрибуция OTel Collector»: один бинарь собирает
  метрики+логи+трейсы+профили и раскладывает по Loki/Mimir/Tempo
  ([docs](https://grafana.com/docs/alloy/latest/)).

### 2.3 VictoriaMetrics (Apache-2.0) — лучший выбор для homelab

[v1.150.0](https://github.com/VictoriaMetrics/VictoriaMetrics/releases/tag/v1.150.0):
одиночный Go-бинарь без зависимостей, все данные в одном каталоге, снапшоты +
vmbackup. Реализует Prometheus querying API (drop-in для Grafana) и принимает
почти все протоколы: remote_write, scrape, Influx, Graphite, Datadog, OTLP
([single-node docs](https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/)).
MetricsQL — расширение PromQL. Vendor-бенчмарки: до 7× меньше RAM и диска, чем
Prometheus/Thanos/Cortex *(цифры производителя)*.

- **Экосистема**: vmagent (сборщик), vmalert (правила → Alertmanager), vmauth
  (auth-прокси), vmctl (миграция) ([components](https://docs.victoriametrics.com/victoriametrics/vmagent/)).
- **VictoriaLogs v1.52.0** — логи с полнотекстовым поиском (LogsQL), принимает
  Fluent Bit/Vector/syslog/journald/OTel;
  [docs](https://docs.victoriametrics.com/victorialogs/). Есть и VictoriaTraces.
- **Compose**: официальные deployment-файлы, включая кластер
  ([deployment/docker](https://github.com/VictoriaMetrics/VictoriaMetrics/tree/master/deployment/docker)).
- **Kubernetes**: официальные Helm-чарты (`victoria-metrics-k8s-stack`,
  `victoria-metrics-single`, …) и оператор с CRD VMServiceScrape/VMRule
  ([helm index](https://docs.victoriametrics.com/helm/), [operator](https://docs.victoriametrics.com/operator/)).
- **Аутентификация**: компоненты голые; штатный паттерн — vmauth спереди,
  есть официальный гайд «Grafana + OIDC через vmauth»
  ([guide](https://docs.victoriametrics.com/guides/grafana-vmauth-openid-configuration/)).

### 2.4 Long-term хранение: Thanos vs Mimir vs Cortex vs remote_write

| Вариант | Модель | Хранилище | Когда брать | Источник |
|---|---|---|---|---|
| Plain Prometheus + remote_write | локальный TSDB + отправка наружу | диск + бэкенд | маленькие инсталляции | [storage](https://prometheus.io/docs/prometheus/latest/storage/) |
| Thanos v0.42.4 | sidecar выгружает TSDB-блоки в S3, Query федерирует | любой object storage | уже есть N Prometheus'ов | [thanos.io](https://thanos.io/) |
| Mimir 3.2.0 | push (remote_write/OTLP), шардируемые микросервисы | object storage | мультиарендность, большой масштаб | [docs](https://grafana.com/docs/mimir/latest/) |
| Cortex v1.21.1 | предок Mimir | object storage | legacy | [cortexmetrics.io](https://cortexmetrics.io/) |
| VictoriaMetrics | одиночный бинарь или кластер | локальный диск | homelab/средний масштаб | [docs](https://docs.victoriametrics.com/victoriametrics/cluster-victoriametrics/) |

Сам VictoriaMetrics позиционирует single-node как замену «умеренных кластеров
Thanos/M3DB/Cortex» *(vendor claim)*; официальный совет — кластерная версия
только после ~1 млн точек/сек ([cluster docs](https://docs.victoriametrics.com/victoriametrics/cluster-victoriametrics/)).

### 2.5 OpenTelemetry в 2026

[OTLP 1.11.0](https://opentelemetry.io/docs/specs/otlp/) стабилен для traces,
metrics и logs (profiles — development): gRPC :4317 / HTTP :4318.
[Collector](https://opentelemetry.io/docs/collector/) (v0.159.0) — приём,
обработка, fan-out; режимы agent/gateway. Semantic conventions v1.44.0
унифицируют атрибуты HTTP/DB/messaging ([semconv](https://opentelemetry.io/docs/specs/semconv/)).
Прометеевский мир принимает OTLP напрямую: Prometheus, Mimir, VictoriaMetrics,
Jaeger v2 построен на фреймворке OTel Collector
([Jaeger intro](https://www.jaegertracing.io/docs/latest/)).

### 2.6 Трейсинг и логи кратко

- **Трейсы**: Jaeger v2.20.0 (CNCF graduated, хранилища ES/OpenSearch/Cassandra/
  ClickHouse/Badger), Tempo (дешёвый object-storage), Zipkin (legacy).
- **Логи**: Loki (лейбл-индекс) ↔ Elasticsearch/OpenSearch (полнотекст) ↔
  ClickHouse-стеки: SigNoz, qryn/Gigapipe (полиглот-API Loki/Tempo/Elastic/Datadog
  поверх ClickHouse — [README](https://raw.githubusercontent.com/metrico/qryn/master/README.md)),
  Quickwit (куплен Datadog в январе 2025), VictoriaLogs.

---

## 3. 🔄 Альтернативные open-source системы

### Классическая инфраструктурная («agent + server»)

| Система | Сильная сторона | Лицензия | K8s | SSO | Источник |
|---|---|---|---|---|---|
| Zabbix 7.4 | Всё: агенты, SNMP, IPMI, JMX, VMware, шаблоны, HA сервера | AGPL-3.0 | офиц. Helm | SAML+LDAP+MFA, **OIDC нет** | [auth docs](https://www.zabbix.com/documentation/current/en/manual/web_interface/frontend_sections/users/authentication) |
| Checkmk Raw | ~2000 плагинов, автообнаружение сервисов | GPL-2.0 | Helm | SAML+LDAP | [docs](https://docs.checkmk.com/) |
| Icinga 2 | Config-as-code, распределённые зоны | GPL-3.0 | community | LDAP; SAML модулями | [auth](https://icinga.com/docs/icinga-web-2/latest/doc/05-Authentication/) |
| Nagios Core | Легаси-стандарт | GPL-2.0 | нет | нет | [repo](https://github.com/NagiosEnterprises/nagioscore) |
| LibreNMS | SNMP-автообнаружение сетевого железа | GPL-3.0 | community | LDAP/HTTP | [repo](https://github.com/librenms/librenms) |

Интересно: Zabbix умеет **читать Prometheus-эндпоинты** нативно (HTTP-agent +
preprocessing + LLD — [docs](https://www.zabbix.com/documentation/current/en/manual/config/items/itemtypes/http/prometheus)),
а Checkmk имеет special agent к Prometheus API
([plugin](https://github.com/Checkmk/checkmk/tree/master/cmk/plugins/prometheus)) —
миры совместимы без дублирования сбора.

### Реалтайм и лёгковесные

- **Netdata** (GPL-3.0) — посекундные метрики per-node, ML-аномалии,
  parent/child стриминг. Docker/K8s официально
  ([docker](https://learn.netdata.cloud/docs/netdata-agent/installation/docker),
  [helm](https://github.com/netdata/helmchart)). SSO — только Netdata Cloud
  ([cloud docs](https://learn.netdata.cloud/docs/cloud)). Отдаёт данные в
  Prometheus remote_write
  ([connector](https://github.com/netdata/netdata/blob/master/src/exporting/prometheus/integrations/prometheus_remote_write.md)).
- **Glances**, **btop** — ad-hoc осмотр, без алертинга.

### Uptime/health-пробы (у вас уже есть)

Uptime Kuma 2.5.0 (MIT, ~90 каналов уведомлений, UI-конфиг, **OIDC-логина нет** —
PR-ы закрыты несклеенными: [#6161](https://github.com/louislam/uptime-kuma/pull/6161));
Gatus (Apache-2.0, config-as-code YAML, **OIDC есть** —
[gatus.io/docs/authentication](https://gatus.io/docs/authentication));
Healthchecks (BSD, heartbeat-пинг для cron/бэкапов); Upptime (GitHub Actions).

### Контейнеры/хост

**Beszel 0.18.8** (MIT, hub+agent, PocketBase/SQLite внутри; CPU/RAM/disk/network/
температуры/GPU/Docker+Podman/systemd; **OAuth2+custom OIDC** — официально
проверен с Authelia, authentik, Pocket ID, ZITADEL, Keycloak —
[beszel.dev/guide/oauth](https://beszel.dev/guide/oauth)); **Scrutiny** (SMART);
**Dozzle** (живые логи контейнеров, **есть OIDC** —
[dozzle.dev/guide/authentication](https://dozzle.dev/guide/authentication)).

### APM / ошибки / all-in-one

| Система | Что это | Лицензия | SSO | Источник |
|---|---|---|---|---|
| Sentry self-hosted | Ошибки+трейсы+replay; минимум 4 CPU/16 GB RAM | FSL-1.1-Apache-2.0 (не OSI) | DIY | [self-hosted](https://develop.sentry.dev/self-hosted/) |
| GlitchTip | Лёгкий Sentry-совместимый | MIT | OIDC/SAML | [docs](https://glitchtip.com/documentation) |
| SigNoz | APM+логи+метрики на ClickHouse, OTel-native | MIT core, EE отдельно | EE-gated | [LICENSE](https://github.com/SigNoz/signoz/blob/main/LICENSE) |
| OpenObserve | Rust single-binary: логи+метрики+трейсы на S3 | AGPL-3.0 | OIDC/LDAP | [repo](https://github.com/openobserve/openobserve) |
| HyperDX | Логи+трейсы на ClickHouse | MIT | — | [repo](https://github.com/hyperdxio/hyperdx) |

### Логи (альтернативы Loki)

- **Elasticsearch**: с августа 2024 triple-license AGPL/SSPL/ELv2, x-pack остаётся ELv2
  ([blog](https://www.elastic.co/blog/elasticsearch-is-open-source-again),
  [LICENSE.txt](https://github.com/elastic/elasticsearch/blob/main/LICENSE.txt));
  SAML/OIDC/LDAP — платные realm'ы.
- **OpenSearch** (Apache-2.0): SAML и OIDC **в бесплатной** security-платформе —
  [SAML](https://docs.opensearch.org/latest/security/authentication-backends/saml/),
  [OIDC](https://docs.opensearch.org/latest/security/authentication-backends/openid-connect/).
- **Graylog Open** (SSPL): MongoDB + OpenSearch, стриминг/pipeline-rules;
  OIDC+SAML документированы ([go2docs.graylog.org](https://go2docs.graylog.org/)).

---

## 4. 💼 Закрытые решения (для контраста)

Все — проприетарный SaaS; интересно, что они **принимают** данные из open-source агентов:

| Продукт | Позиционирование | Принимает от OSS | SSO |
|---|---|---|---|
| Datadog | Эталон отрасли, per-host pricing, 800+ интеграций | Prometheus-скрейпы, OTLP, Fluent Bit | SAML ([docs](https://docs.datadoghq.com/account_management/saml/)) |
| New Relic | Per-GB, щедрый free tier (100 GB/мес) | OTLP | SAML |
| Dynatrace | OneAgent auto-instrumentation + Davis AI | OTLP | SAML |
| Splunk | Логи/SIEM, лицензия по индексу; куплен Cisco (2025) | HEC ← Fluent Bit/Vector | SAML |
| Sumo Logic | SaaS-аналитика логов | свой OTel-distribution | SAML |
| Better Stack | Uptime+status page+логи, дружелюбный free tier | HTTPS/Vector | SAML |
| Grafana Cloud | Managed-версия всего стека выше, бесплатный tier навсегда | remote_write, OTLP, Fluent Bit→Loki | SAML/OIDC |

Гибридный паттерн для homelab: держать данные локально, а Alloy/OTel Collector
зеркалирует выбранные потоки в облако как offsite-копию.

---

## 5. 🔗 Как компоненты взаимодействуют

Документированные связки:

1. **remote_write** — Prometheus → VictoriaMetrics/Mimir/Cortex/Thanos Receive
   ([storage](https://prometheus.io/docs/prometheus/latest/storage/),
   [VM↔Prometheus](https://docs.victoriametrics.com/victoriametrics/integrations/prometheus/)).
2. **Alloy/OTel Collector как центральный пайплайн** — скрейп + приём OTLP +
   fan-out в Loki/Mimir/Tempo ([Alloy](https://grafana.com/docs/alloy/latest/)).
3. **Grafana как единый UI** — datasource'ы ко всему; exemplars → Tempo;
   derived fields из Loki → Tempo ([Tempo](https://grafana.com/docs/tempo/latest/)).
4. **Alertmanager принимает от всех движков правил** — Prometheus, vmalert,
   Grafana (как contact point) ([vmalert](https://docs.victoriametrics.com/victoriametrics/vmalert/)).
5. **Мосты между мирами**: Zabbix читает Prometheus-эндпоинты; Netdata пишет
   remote_write; snmp_exporter/ipmi_exporter подтягивают сетевое железо и IPMI
   в Prometheus-мир ([snmp_exporter](https://github.com/prometheus/snmp_exporter));
   Fluent Bit/Vector одним демоном кормят Loki+Elastic+Graylog+Datadog одновременно
   ([Fluent Bit outputs](https://docs.fluentbit.io/manual/pipeline/outputs/loki)).

### Типовая минимальная топология homelab (Compose)

```
 exporters ──pull──▶ vmagent ──remote_write──▶ VictoriaMetrics ◀──OTLP── Alloy
 (node/cadvisor/                                     │               │
  blackbox/app /metrics)                    vmalert ─┘               ▼
                                               │                 Loki (логи)
                                               ▼                 Tempo (трейсы)
                                        Alertmanager ─▶ Telegram/webhook
                                               │
                                    Grafana (OIDC через generic OAuth)
                                    datasources: VM, Loki, Tempo
```

Ещё более лёгкий вариант — вообще без Prometheus: VictoriaMetrics сам скрейпит
exporters, vmalert алертит, Grafana рисует — один compose-файл
([VM architectures](https://docs.victoriametrics.com/guides/vm-architectures/)).

### Типовая топология Kubernetes

- **Prometheus-флейвор**: kube-prometheus-stack (Operator + Prometheus +
  Alertmanager + node-exporter DaemonSet + kube-state-metrics + Grafana);
  цели объявляются label-селекторами в ServiceMonitor; retention — Thanos sidecar
  или remote_write в Mimir/VM ([chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)).
- **VM-флейвор**: victoria-metrics-k8s-stack c CRD VMServiceScrape/VMRule
  ([operator](https://docs.victoriametrics.com/operator/)).
- **All-in-one**: SigNoz Helm-чарт для OTLP-first подхода
  ([install](https://signoz.io/docs/install/kubernetes/)).

---

## 6. 📊 Сводное сравнение

### 6.1 Основные стеки

Легенда: ✅ отлично · 🔧 частично/через обвязку · ❌ нет · 💰 платно

| Критерий | Prometheus-стек | LGTM (Grafana) | VictoriaMetrics | Zabbix | Netdata | SigNoz | OpenObserve |
|---|---|---|---|---|---|---|---|
| Лицензия | Apache-2.0 ✅ | AGPLv3 ⚠️ | Apache-2.0 ✅ | AGPL-3.0 ⚠️ | GPL-3.0 ⚠️ | MIT core ✅ | AGPL-3.0 ⚠️ |
| Метрики | ✅ эталон | ✅ (Mimir) | ✅ + MetricsQL | ✅ | ✅ посекундно | ✅ | ✅ |
| Логи | ❌ | ✅ Loki | ✅ VictoriaLogs | ✅ (триггеры) | ⚠️ | ✅ | ✅ |
| Трейсы | ❌ | ✅ Tempo | ✅ VictoriaTraces | ❌ | ❌ | ✅ | ✅ |
| Расход ресурсов | 🟡 средний | 🟡 средний | 🟢 низкий* | 🟡 средний | 🟢 низкий | 🔴 высокий (ClickHouse) | 🟢 низкий |
| Docker Compose | 🔧 собирать самому | 🔧 | ✅ официальные файлы | ✅ офиц. репо | ✅ | ✅ one-click | ✅ |
| Kubernetes | ✅ operator+chart | ✅ charts | ✅ chart+operator | ✅ helm | ✅ helm | ✅ helm | ✅ in-repo |
| HA | 🔧 дубликаты | ✅ | 🔧 vmagent double-write / ✅ cluster | ✅ серверный HA | ✅ parent/child | 🔧 | 🔧 |
| Алертинг | ✅ Alertmanager | ✅ unified | ✅ vmalert | ✅ зрелейший | ✅ | ✅ | ✅ |
| **OIDC/OAuth2** | ❌ (basic/TLS only) | ✅ OSS generic OAuth | ❌ → vmauth 🔧 | ❌ | ❌ (Cloud only) | 💰 EE | ✅ |
| **SAML** | ❌ | 💰 Enterprise | ❌ | ✅ | 💰 Cloud top | 💰 EE | ❌ |
| **LDAP** | ❌ | 💰 Enterprise | ❌ | ✅ | ❌ | ❌ | ✅ |
| Порог входа | 🟡 | 🟡 | 🟢 | 🔴 | 🟢 | 🟡 | 🟢 |

\* vendor-бенчмарки VictoriaMetrics: до 7× меньше RAM/диска чем Prometheus/Thanos/Cortex
([docs](https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/)).

Источники по SSO-строке: [Prometheus security model](https://prometheus.io/docs/operating/security/),
[Grafana generic OAuth](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-authentication/generic-oauth/)
(PKCE, JWKS, role mapping — в OSS; SAML/LDAP — Enterprise),
[vmauth OIDC guide](https://docs.victoriametrics.com/guides/grafana-vmauth-openid-configuration/),
[Zabbix auth](https://www.zabbix.com/documentation/current/en/manual/web_interface/frontend_sections/users/authentication),
[Netdata Cloud](https://learn.netdata.cloud/docs/cloud),
[SigNoz LICENSE](https://github.com/SigNoz/signoz/blob/main/LICENSE).

### 6.2 🔐 SSO/OIDC: кто пускает через ваш IdP

У вас три OIDC-провайдера: Authentik, Pocket-ID, Zitadel.

| Компонент | Нативный OIDC | Как подключить к Authentik/Pocket-ID/Zitadel |
|---|---|---|
| Grafana | ✅ generic OAuth: discovery, PKCE, JWKS, role_attribute_path | Прямо ([doc](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-authentication/generic-oauth/)) |
| Gatus | ✅ OIDC/OAuth2 | Прямо ([doc](https://gatus.io/docs/authentication)) |
| Beszel | ✅ OAuth2+custom OIDC | Прямо; провайдер проверялся именно с authentik/Pocket ID/ZITADEL ([doc](https://beszel.dev/guide/oauth)) |
| Dozzle | ✅ OIDC | Прямо ([doc](https://dozzle.dev/guide/authentication)) |
| Uptime Kuma | ❌ (PR закрыты) | oauth2-proxy / Traefik forward-auth перед ним |
| Prometheus / Alertmanager / Pushgateway | ❌ | oauth2-proxy / basic-auth за прокси ([guide](https://prometheus.io/docs/guides/basic-auth/)) |
| VictoriaMetrics / vmalert | ❌ | vmauth + официальный OIDC-гайд |
| Loki / Tempo / Mimir (OSS) | ❌ (только tenant-заголовки) | Доступ только через Grafana или прокси |
| Zabbix | ❌ (только SAML) | SAML-мост (Keycloak/Authentik SAML) либо forward-auth |
| OpenSearch | ✅ бесплатно | Прямо ([OIDC](https://docs.opensearch.org/latest/security/authentication-backends/openid-connect/)) |
| Graylog | ✅ | Прямо ([go2docs](https://go2docs.graylog.org/)) |
| GlitchTip | ✅ | Прямо ([docs](https://glitchtip.com/documentation)) |
| OpenObserve | ✅ | Прямо ([docs](https://openobserve.ai/docs/)) |
| Sentry self-hosted | ⚠️ DIY через sentry.conf.py | Сложно |
| Netdata local agent | ❌ | Только Netdata Cloud |

Практический вывод: **Grafana становится единственной UI-точкой входа с OIDC**,
а «голые» компоненты (Prometheus, VM, Alertmanager) прячутся за ней или за
oauth2-proxy — это ровно тот паттерн, который рекомендуют сами документы
Prometheus ([security model](https://prometheus.io/docs/operating/security/)).

---

## 7. 🏠 Аудит: что из установленного поддерживает мониторинг

Живые проверки выполнены curl-ом изнутри сети Docker (пометка ✅LIVE), конфиги —
из репозитория. Состояние на 2026-08-21.

### 7.1 Текущее состояние слоя мониторинга

| Уже работает | Роль | Пробел |
|---|---|---|
| Gatus v5.36 | 22 health-проверки (Homepage, Beszel, Arcane, WUD, Cup, Nextcloud `/status.php`, Forgejo `/api/healthz`, code-server `/healthz`, Authentik ready, Pocket-ID discovery, LocalAI `/readyz`, Immich ping, Dawarich, Jellyfin `/health`, Navidrome `/ping`, Stirling-PDF, HA, Technitium DNS…) | `metrics: true` выключен |
| Uptime Kuma v2 | Внешние пробы + status page | `/metrics` заперт basic-auth без API key |
| Beszel 0.18 | Метрики хоста и контейнеров | Не экспортирует в Prometheus |
| Traefik v3.7 | — | **`metrics.prometheus` выключен** (LIVE: `/metrics`=404) |
| Vault | — | Нет `telemetry`-стансы в vault.hcl |
| Synapse | — | `enable_metrics` выключен |
| k3s metrics.yaml | metrics-server для будущего k3s | Не относится к app-метрикам |

### 7.2 Таблица по приложениям

✅ включено сейчас · 🔧 поддерживается, выключено (как включить) · ❌ не найдено · 📦 exporter

| Приложение | Метрики | Health | Комментарий |
|---|---|---|---|
| **Traefik** | 🔧 `metrics.prometheus: {}` → `/metrics` ([docs](https://doc.traefik.io/traefik/observability/metrics/prometheus/)) | `/ping` ✅LIVE | Самая простая крупная победа; JSON access-log тоже 🔧 |
| **Authentik** | ✅ **уже отдаёт** `:9300/metrics` (django-prometheus, 76 семейств метрик) ✅LIVE ([docs](https://docs.goauthentik.io/sys-mgmt/ops/monitoring/)) | `/-/health/ready/` ✅LIVE | Просто начать скрейпить |
| **WUD** | ✅ **уже отдаёт** `/metrics` (70 семейств) ✅LIVE | `/health` ✅LIVE | Просто начать скрейпить |
| **Technitium** | 🔧 `GET /api/dashboard/metrics/text` (:5380, Bearer-токен) ([changelog](https://github.com/TechnitiumSoftware/DnsServer/blob/master/CHANGELOG.md)) | DNS-проба в Gatus ✅ | Есть community-exporters |
| **Synapse** | 🔧 `enable_metrics: true` + listener `[metrics]` → `/_synapse/metrics` ([howto](https://matrix-org.github.io/synapse/latest/metrics-howto.html)) | `/health` ✅LIVE | Богатые метрики Matrix |
| **LiveKit** | 🔧 блок `prometheus:` в конфиге | wget :7880 ✅ | Для element-звонков |
| **Forgejo** | 🔧 `[metrics] ENABLED=true` + TOKEN ([cheat sheet](https://forgejo.org/docs/latest/admin/config-cheat-sheet/)) | `/api/healthz` ✅LIVE | Скрейп с `?token=` |
| **Immich** | 🔧 `IMMICH_TELEMETRY_INCLUDE=all` → порты 8081/8082 ([docs](https://docs.immich.app/features/monitoring/)) | `/api/server/ping` ✅LIVE | JSON-логи 🔧 `IMMICH_LOG_FORMAT=json` |
| **Dawarich** | 🔧 `PROMETHEUS_EXPORTER_ENABLED=true` + METRICS_USERNAME/PASSWORD ([docs](https://dawarich.app/docs/self-hosting/monitoring/prometheus/)) | `/api/v1/health` ✅ | Одна пара env |
| **Navidrome** | 🔧 `ND_PROMETHEUS_ENABLED=true` ([docs](https://www.navidrome.org/docs/usage/integration/monitoring/)) | `/ping` ✅LIVE | Готовые Grafana-дашборды #24397/#18038 |
| **Home Assistant** | 🔧 интеграция `prometheus:` + long-lived token ([integration](https://www.home-assistant.io/integrations/prometheus/)) | `/` ✅LIVE | hostNetwork — учесть в k3s |
| **Vault** | 🔧 `telemetry {}` → `/v1/sys/metrics` с заголовком `Accept: prometheus/telemetry` ([docs](https://developer.hashicorp.com/vault/docs/configuration/telemetry)) | `/v1/sys/health` ✅LIVE (503 sealed) | Алерт на sealed-state критичен |
| **Gatus** | 🔧 `metrics: true` в config.yaml | API statuses ✅LIVE | Одна строка |
| **Stalwart** | 🔧 Telemetry→Metrics→Prometheus ([docs](https://stalw.art/docs/telemetry/metrics/prometheus/)) | ⚠️ нет /healthz | Крупная победа для почты |
| **LocalAI** | 🔧 встроенный `/metrics` (за API-key) | `/readyz` ✅LIVE | Скрейп с ключом |
| **talk-hpb (eturnal)** | 🔧 модуль `mod_stats_prometheus` (:8081) ([eturnal](https://eturnal.net/doc/#Module_Configuration)) | ⚠️ | TURN-метрики |
| **Jitsi jicofo/prosody** | 🔧 REST-stats/mod_prometheus | ⚠️ | JVB в стеке нет |
| **wg-easy** | 🔧 включается в админке | — | Контейнер не запущен на момент аудита |
| **Zitadel** | ⚠️ `/metrics` есть в main-ветке, в v4.17 LIVE 404 | `/healthz` ✅LIVE | Перепроверить после апгрейда |
| **Pocket-ID** | ❌ | `/healthz`=204 ✅LIVE | HTTP-пробы достаточно |
| **Nextcloud** | ❌ ядро | `/status.php` ✅LIVE | 📦 [nextcloud-exporter](https://github.com/xperimental/nextcloud-exporter) |
| **Jellyfin** | ❌ | `/health` ✅LIVE | 📦 community-плагины, низкий приоритет |
| **Paperless-ngx** | ❌ | `/api/health/` (302 наружу) | Container healthcheck достаточен |
| **Seafile CE** | ❌ (Pro-only статистика) | `/api2/ping/` ✅LIVE | — |
| **OnlyOffice DS** | ⚠️ ds-metrics фактически выключен | `/healthcheck` ✅LIVE | Healthcheck достаточен |
| **code-server, Stirling-PDF, Cup, Arcane, Homepage, Infisical, pgweb, Structurizr, Mermaid, Lute, Sure, Spotdl, 3x-ui, Element-web, lk-jwt, coturn, Bulwarkmail** | ❌ | у каждого есть health/TCP-проба (все в Gatus) | Оставить на уровне проб |
| **PostgreSQL ×10** (shared, forgejo, dawarich, element, immich, infisical, nextcloud, paperless, sure, zitadel, authentik) | ❌ | `pg_isready` везде | 📦 [postgres_exporter](https://github.com/prometheus-community/postgres_exporter) — один multi-target покрывает все |
| **Redis/Valkey ×7** | ❌ | `redis-cli ping` | 📦 [redis_exporter](https://github.com/oliver006/redis_exporter) (multi-target) |
| **MariaDB (seafile)** | ❌ | mariadb-admin ping | 📦 [mysqld_exporter](https://github.com/prometheus/mysqld_exporter) |
| **Beszel** | ❌ экспорта нет | `/api/health` ✅LIVE | Остаётся отдельным силосом до node_exporter |

### 7.3 🎯 Быстрые победы (по убыванию ценности/затрат)

1. **Traefik**: одна строка `metrics.prometheus: {}` → метрики всего reverse-proxy.
2. **Authentik и WUD**: уже отдают `/metrics` — только добавить scrape-target.
3. **postgres_exporter + redis_exporter + mysqld_exporter**: ~20 контейнеров одним махом.
4. **Gatus** `metrics: true`; **Uptime Kuma** — выпустить API key.
5. **Env-flip**: Dawarich, Navidrome, Immich, Synapse, Forgejo, Stalwart, Vault.
6. **blackbox_exporter** — перенести часть TCP/HTTP/DNS-проб из Gatus в метрики (TLS-expiry как алерт, а не только проба).

---

## 8. 🗺️ Рекомендация по этапам

**Этап 0 — уже сделано:** Gatus (probes-as-code), Uptime Kuma (внешние пробы),
Beszel (хост/контейнеры), k3s metrics-server подготовлен.

**Этап 1 — метрическое ядро (Compose, ~30 мин):**
`VictoriaMetrics + vmagent + vmalert + Grafana + Alertmanager` одним compose-файлом
([официальные deployment-файлы](https://github.com/VictoriaMetrics/VictoriaMetrics/tree/master/deployment/docker));
Grafana — за Traefik с OIDC через Authentik (generic OAuth); vmagent скрейпит
quick-wins из §7.3; vmalert → Alertmanager → Telegram. Альтернатива классикой:
Prometheus + Alertmanager + Grafana — больше канонических примеров, но нет
официального compose и выше расход RAM.

**Этап 2 — логи (опционально):** Alloy (сбор docker-логов) → Loki или
VictoriaLogs; JSON-логи у Immich/Traefik/Stalwart/Vault уже включаются env-ами.

**Этап 3 — k3s:** kube-prometheus-stack ИЛИ victoria-metrics-k8s-stack —
оба дают паттерн «приложение объявляет ServiceMonitor, скрейп настраивается сам»;
ваши Compose-привычки (config-as-code из Git) переносятся 1:1 в CRD/labels.

**SSO-принцип:** всё, что умеет OIDC (Grafana, Gatus, Beszel, Dozzle) — напрямую
через Authentik/Pocket-ID/Zitadel; всё, что не умеет (Prometheus, VM, Alertmanager,
Loki) — только через Grafana или за oauth2-proxy/vmauth; прямого трафика наружу
не публиковать.
