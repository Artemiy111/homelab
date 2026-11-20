# Observability: инструменты, стеки и ресурсы

Это исследование инструментов и технологий для observability: паспорта продуктов,
официальные модели по ресурсам, расчёты под заданный масштаб и профили эксплуатации.
Версии сверены через GitHub Releases API и страницы релизов вендоров. Цифры о потреблении
ресурсов взяты из официальной документации capacity planning каждого проекта.

## Вывод

1. **Мониторинг — конвейер, а не продукт.** Сбор → транспорт → хранение →
   визуализация → алертинг → маршрутизация. Продукты закрывают разные слои, и
   «сравнить Zabbix с Loki» нельзя — у них разное назначение.
2. **Grafana — не база данных и не конкурент VictoriaMetrics.** Это UI поверх
   чужих datasource'ов. Корректное сравнение — «стек VictoriaMetrics» против
   «стека Grafana (Mimir/Loki/Tempo + Grafana)».
3. **Ресурсы метрик определяет не объём данных, а кардинальность.** 1000-серий
   node_exporter на узел, 1000–5000 у типичного приложения с гистограммами,
   десятки тысяч у kube-state-metrics в большом кластере. Высокая
   кардинальность (лейблы с ID, URL, `pod_name`) увеличивает RAM, диск и
   время запросов одновременно во всех TSDB.
4. **По диску Prometheus-формат стоит 1–2 байта на sample** (официальная
   формула Prometheus), VictoriaMetrics — около 1 байта по документации.
5. **Zabbix — другой класс.** «Всё в одной коробке»: база + сервер + веб-фронтенд
   + агенты, SNMP/IPMI/JMX, шаблоны. Официальная таблица — контраст с Prometheus-миром.
6. **ELK/OpenSearch — самая дорогая связка по RAM/диску/операциям** среди логовых
   систем, но даёт самый сильный полнотекстовый поиск и SIEM.
7. Два профиля эксплуатации — **хоумлаб и энтерпрайб** — что меняет выбор:
   HA, мультиарендность,compliance, операционная сложность и бюджет.

## 1. Что с чем сравнивать

| Слой | Что делает | Кандидаты | Чем платим |
|---|---|---|---|
| Инструментирование | экспорт метрик/трейсов из приложения | клиентские библиотеки, OTel SDK, eBPF (Beyla) | CPU приложения, иногда latency |
| Сбор | опрос целей, приём push | Prometheus, vmagent, OTel Collector, Alloy, Telegraf, Zabbix agent/proxy | RAM + CPU на каждом узле |
| Транспорт | формат и доставка | exposition, remote write, OTLP, syslog | сеть, буферы |
| Хранение метрик (TSDB) | индекс + сжатые чанки | VictoriaMetrics, Prometheus, Mimir, Thanos, Zabbix DB | RAM (кардинальность) + диск |
| Хранение логов | индекс/колонки + сжатие | Loki, VictoriaLogs, Elasticsearch, OpenSearch, ClickHouse-стеки | диск + RAM на индексацию |
| Визуализация | дашборды, explore | Grafana, vmui, Kibana, Zabbix frontend | 0,5–2 ГБ RAM |
| Алертинг | правила по данным | vmalert, Prometheus rules, Grafana Alerting, Zabbix triggers | CPU при частых правилах |
| Маршрутизация | группировка, тишина, каналы | Alertmanager, vmalert → webhook | копейки |

Отсюда следствия, на которых ломаются большинство сравнений:

- **Против «VictoriaMetrics vs Prometheus» корректно сравнивать только
  хранилище+сбор+правила.** Grafana в эту пару не входит: она одинаково
  работает с обоими через Prometheus querying API.
- **Против «ELK» корректно сравнивать Loki/VictoriaLogs.**
- **Zabbix нельзя разложить по слоям** — это монолит «агент + сервер + база +
  фронтенд + триггеры».

Три величины, которые определяют цену:

| Величина | Что это | Почему важна |
|---|---|---|
| Active series | серия, обновлявшаяся за последний час | RAM: индекс и голова чанков живут в памяти |
| Ingestion rate, sample/s | серии / интервал скрейпа | CPU и диск: `серии / интервал` |
| Log volume, ГБ/день | объём сырых логов | диск, CPU на индексацию, object storage |

## 2. Сводная матрица возможностей (визуальная)

**Легенда:** ✅ есть/работает · 🟡 есть с ограничениями/доработками ·
🔧 через обвязку/не нативно · ❌ нет · 💰 платно · 🔴 дорого
(ресурсы — по данным вендоров и в §4/§5).

Примеры: "🔴 дорого" у Prometheus-стека по кардинальности — при 100 тыс. серий это
16 ядер/64 ГБ плюс диск под историю. "🔧 через обвязку" у VictoriaMetrics по OIDC —
компоненты голые, паттерн есть (vmauth + официальный гайд), но не припаяны к
коробке.

| Параметр | VictoriaMetrics | Prometheus-стек | LGTM | Zabbix |
|---|---|---|---|---|
| Метрики | ✅ | ✅ эталон | ✅ (Mimir или Thanos) | ✅ (другая модель — item'ы) |
| Логи | ✅ VictoriaLogs / 🔧 Loki | ❌ | ✅ Loki / ✅ VictoriaLogs | ✅ триггеры, не полнотекст |
| Трейсы | ✅ VictoriaTraces | ❌ | ✅ Tempo | ❌ |
| OIDC/SAML | 🔧 vmauth | ❌ (basic/TLS only) | ✅ Grafana; SAML 💰 EE | SAML ✅, OIDC ❌ |
| Лицензия | Apache-2.0 ✅ | Apache-2.0 ✅ | AGPLv3 ⚠️ | AGPL-3.0 ⚠️ |
| Порог входа | 🟢 | 🟡 | 🟡 | 🔴 |
| Kubernetes | ✅ operator+chart | ✅ operator+kube-prometheus-stack | ✅ charts | ✅ helm |
| HA | ✅ в кластере | 🔧 дубликаты | ✅ Grafana; Mimir RRU | ✅ серверный HA |

Полная матрица по параметрам («что с чем работает» — интеграции, кардинальность,
down-sampling, мультиарендность) — в §3.5 и §5.4.

## 3. Метрики (TSDB)

### 3.1 VictoriaMetrics

Один Go-бинарь без зависимостей, все данные в одном каталоге, снапшоты и
vmbackup. Реализует Prometheus querying API и потому drop-in для Grafana;
MetricsQL — надмножество PromQL. Принимает remote write, собственный скрейп,
Influx, Graphite, OpenTSDB, Datadog, OTLP.

- **Экосистема**: vmagent (сбор), vmalert (правила → Alertmanager), vmauth
  (auth-прокси), vmctl (миграция), vmbackup/vmrestore, vmgateway.
- **Кластер**: `vminsert`/`vmselect`/`vmstorage`; вендор предпочитает ≥10 маленьких
  `vmstorage` вместо 3 больших (при отказе одной ноды нагрузка растёт на 1/9, а
  не на 1/2) — [cluster docs](https://docs.victoriametrics.com/victoriametrics/cluster-victoriametrics/).
- **Устойчивость к рестартам**: дедупликация по `-dedup.minScrapeInterval`.
- **Enterprise (платный регион)**: даунсэмплинг, multiple retentions по
  датасетам, авто-дискавери `vmstorage`, мониторинг VM, mTLS между компонентами
  кластера, multitenant vmalert, IP-фильтрация на vmauth
  ([enterprise](https://docs.victoriametrics.com/victoriametrics/enterprise/)).
- **Аутентификация в OSS**: только vmauth спереди — есть официальный
  [гайд Grafana+OIDC через vmauth](https://docs.victoriametrics.com/guides/grafana-vmauth-openid-configuration/).

### 3.2 Prometheus

Эталон модели: pull, экспозиция, PromQL, локальный TSDB, rules, Alertmanager.
OTLP приём, experimental remote write 2.0, agent mode для сбора
([overview](https://prometheus.io/docs/introduction/overview/)).

- **Хранение**: 2-часовые блоки, компакция до 10% retention, WAL; NFS не
  поддерживается ([storage](https://prometheus.io/docs/prometheus/latest/storage/)).
- **HA**: дубликаты с дедупликацией выше по стеку; Alertmanager — gossip
  ([HA](https://prometheus.io/docs/alerting/latest/high_availability/)).
- **Доступ**: TLS + basic auth; OIDC/SAML/LDAP нет ни у сервера, ни у
  Alertmanager — «не доверенным пользователям не давайте HTTP-доступ»
  ([security model](https://prometheus.io/docs/operating/security/)).
- **Плюс**: максимум примеров, интеграций и дашбордов; контрастный паспорт для
  кардинальности.

### 3.3 Mimir и Thanos

| | Mimir | Thanos |
|---|---|---|
| Модель | push (remote write/OTLP), микросервисы, шардирование | sidecar/Receiver поверх существующих Prometheus, блоки в object storage |
| Мультиарендность | да (первоклассная) | через remote write; не при скрейпе |
| Когда | десятки млн серий, центральная платформа | уже есть парк Prometheus и нужна только история |
| Ресурсы | см. §4.1 | см. §4.1 |

### 3.4 Zabbix

Монолит «агент + сервер + прокси + БД + фронтенд». Сильная сторона — не
Prometheus-мир, а инфраструктура: SNMP, IPMI, JMX, VMware, traps, шаблоны на
тысячи устройств, LLD-автообнаружение, готовые триггеры.

- **Аутентификация**: internal, HTTP, LDAP, SAML 2.0, MFA; **OIDC нет**
  ([auth docs](https://www.zabbix.com/documentation/current/en/manual/web_interface/frontend_sections/users/authentication)).
- **Умеет читать Prometheus-эндпоинты** через HTTP agent + preprocessing + LLD
  ([docs](https://www.zabbix.com/documentation/current/en/manual/config/items/itemtypes/http/prometheus))
  — миры совместимы без двойного сбора.
- **Модель данных** — item/host/trigger, а не серии: для сравнения ресурсов
  см. §4.2.
- **Enterprise-функции**: SAML, MFA, TimescaleDB/Elasticsearch как бэкенд
  истории значений, распределённые прокси для удалённых сетей, богатые
  отчёты и эскалации, alertmanager-интеграции
  ([Zabbix docs](https://www.zabbix.com/documentation)).

### 3.5 Матрица параметров (метрики)

| Параметр | VictoriaMetrics | Prometheus | Mimir | Zabbix |
|---|---|---|---|---|
| Лицензия | Apache-2.0 | Apache-2.0 | AGPL-3.0 (EE отдельно) | AGPL-3.0 |
| Язык запросов | MetricsQL (надмножество PromQL) | PromQL | PromQL | свой, SQL по БД |
| Приём | remote write, scrape, Influx, Graphite, OTLP, Datadog | scrape, remote write, OTLP | remote write, OTLP | агенты, SNMP, IPMI, HTTP-agent, Prometheus-эндпоинты |
| Модель данных | серии, как у Prometheus | серии | серии | item/host/trigger |
| Кардинальность | до 50 млн серий на ноде (вендор) | десятки млн серий | десятки млн серий | не масштабируется, но и так достаточно |
| Downsampling | Enterprise | нет (recording rules) | нет | нет |
| Мультиарендность | в кластере (EE) | нет | да (RRU, до 10 000 тенантов/shard) | нет |
| Алертинг | vmalert | rules + Alertmanager | ruler + Alertmanager | triggers |
| Бэкап | vmbackup | снапшоты | object storage | дамп БД |

## 4. Метрики: ресурсы и методики

### 4.1 Модели вендоров

#### VictoriaMetrics

- Одиночный узел работает стабильно при **1,5+ млн sample/s** и **50+ млн
  активных серий** на production ([case studies](https://docs.victoriametrics.com/victoriametrics/casestudies/)).
- «Ожидаемое» использование: **>1 ядра на 100 тыс. sample/s на активные
  серии** — признак нехватки RAM ([troubleshooting](https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/)).
- Диск: формула из [sizing guide](https://docs.victoriametrics.com/guides/understand-your-setup-size/):
  `байт/sample × samples × RF × (retention + 1 цикл) × 1.25`, индекс ≈20% данных
  (до 50%+ при высокой кардинальности), держать ≥20% свободного места.
- При типичном масштабе одной ноды — от единиц до нескольких миллионов
  серий — ресурсы от сотен МБ до десятков ГБ RAM; конкретное значение — из
  замера на ваших данных или у вендора (§4.2).

#### Prometheus

- Хранение: «средне 2 байта на sample» — верхняя граница для планирования;
  формула `needed_disk = retention × samples/s × bytes/sample` и буфер под
  compaction (см. таблицу в [storage](https://prometheus.io/docs/prometheus/latest/storage/)).
- RAM: официальной нормы нет; на той же кардинальности, что и Mimir, ожидаем
  единицы ГБ (§4.2).

#### Mimir

Результаты вендора ([capacity planning](https://grafana.com/docs/mimir/latest/manage/run-production-environment/planning-capacity/),
холодный профиль, без перехода на heavy operators):

| Компонент | Нагрузка |
|---|---|
| distributor | 1 ядро + 1 ГБ на 25 тыс. sample/s |
| ingester | 1 ядро + 2,5 ГБ + 5 ГБ диска на 300 тыс. серий в памяти (RF=3 по умолчанию) |
| querier | 1 ядро + 1 ГБ на 250 QPS |
| store-gateway | 1 ядро + 1 ГБ на 10 QPS, 13 ГБ диска на 1 млн серий |
| compactor | 1 ядро + 4 ГБ + 300 ГБ диска на 20 млн серий |

Для потока из 151 тыс. серий (или любой средней точки — 10–100 тыс.) суммарно
по формулам — единицы ГБ RAM на object storage, +50% запаса на пики.

### 4.2 Сценарий: средний объём данных (сотни тысяч серий, 10–30 тыс. dps, 30 дней)

| Продукт / стек | Оценка RAM | Диск (30 дней) | Методика |
|---|---|---|---|
| VictoriaMetrics | 0,5–3 ГБ | ~2–10 ГБ | вендор: «>1 ядра на 100 тыс. dps = мало RAM» ([§4.1](#41-модели-вендоров)); формулы диска из [sizing guide](https://docs.victoriametrics.com/guides/understand-your-setup-size/) |
| Mimir (RF=3) | ~3–5 ГБ | object storage + store-gateway ~13 ГБ/1 млн серий | §4.1 |
| Zabbix | 16–32 ядра, 64–96 ГБ | БД на отдельном сервере | §3.4 |
| Loki (HA-монолит, ~10–20 ГБ/день) | ~1–3 ГБ | ~1.5–2× объёма | [Loki sizing](https://grafana.com/docs/loki/latest/setup/size/)

### 4.3 Как читать вендорские бенчмарки

VictoriaMetrics заявляет «до 7× меньше RAM и диска, чем Prometheus/Thanos/Cortex».
Это маркетинговые верхние границы на специально подобранных данных: полезны как
порядок величины, не как обещание. Подтверждение можно попросить у вендора:
[benchmark on node_exporter](https://valyala.medium.com/prometheus-vs-victoriametrics-benchmark-on-node-exporter-metrics-4ca29c75590f).

## 5. Логи (TSDB-системы)

### 5.1 Loki

Порядок цены: чем больше объём логов, тем оправданнее object storage; чем
больше интерактивных запросов — тем строже индекс.

- **Хранение**: object storage + локальные блоки, сжатие чанков (snappy/zstd),
  индекс только по лейблам
  ([architecture](https://grafana.com/docs/loki/latest/get-started/architecture/)).
- **Режимы**: монолит до ~20 ГБ/день ([deployment modes](https://grafana.com/docs/loki/latest/get-started/deployment-modes/));
  старый SSD-mode (simple-scalable) — устарел, удалён в Loki 4.0; путь — microservices.
- **Ресурсы (vendor-benchmarks)** — [size the cluster](https://grafana.com/docs/loki/latest/setup/size/):
  - HA-монолит, <100TB/мес (3TB/день): всего ~38 CPU, ~59 ГиБ RAM (единовременно).
  - 100TB–1PB/мес (3–30TB/день): ~431 CPU, ~857 ГиБ.
  - 1PB/мес (30TB/день): ~1221 CPU, ~2235 ГиБ.
- **Операционные последствия**: положить `request_id` в лейбл — получить
  тысячи стримов; экономика при запросах по полному тексту.
- **Enterprise**: RRU — кластеризация без режима microservices (репликация подов,
  автоматическая ребалансировка); на k8s — ECK, минимум 3 master-eligible
  ([size the cluster](https://grafana.com/docs/loki/latest/setup/size/)).

### 5.2 Elasticsearch

- **Heap**: ≤50% RAM узла, `Xms=Xmx`, auto-sizing по умолчанию
  ([jvm settings](https://www.elastic.co/docs/reference/elasticsearch/jvm-settings)).
- **Шарды**: 10–50 ГБ, <200 млн документов на шард
  ([size your shards](https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/size-shards)).
- **Master-eligible узлы**: <3000 индексов на 1 ГБ heap; ≥3 master-eligible в кластере.
- **Kibana**: 2–4 ГБ на старт; 8–16 ГБ — с 100+ дашбордами; ≥2 ГБ для работы
  над SLO ([Kibana memory](https://www.elastic.co/docs/deploy-manage/production-guidance/kibana-configure-memory)).
- **Лицензия**: triple license (AGPLv3, SSPL, ELv2); см. [LICENSE.txt](https://github.com/elastic/elasticsearch/blob/main/LICENSE.txt).
- **Приём**: Logstash, Beats (Filebeat, Metricbeat), нативный push из OTLP/OTel; см. §3.3 в observability-standards.

### 5.3 VictoriaLogs

- Вендор заявляет: до 30× меньше RAM и 15× меньше диска, чем Elasticsearch и
  Grafana Loki на один и тот же объём ([VictoriaLogs docs](https://docs.victoriametrics.com/victorialogs/)).
- Компактный, стабильный профиль: один бинарь без зависимостей, LogsQL;
  `-retention.maxDiskSpaceUsageBytes` — кап объёма диска; сжатие вендора —
  порядок 10× над сырыми логами, колонко-ориентированный движок.

### 5.4 Матрица параметров (логи)

| Параметр | Loki | Elasticsearch | VictoriaLogs |
|---|---|---|---|
| Лицензия | AGPL-3.0 | triple (AGPL/SSPL/ELv2) | Apache-2.0 |
| Индекс | только по лейблам (stream) | полнотекст (Lucene) | битовые индексы по полям |
| Запросы | LogQL (сначала лейблы, потом текст) | Query DSL, SQL | LogsQL (полнотекст) |
| Сжатие | порядок 5–10× (при docker-логах) | меньше (индекс ≈ данным) | порядок 10×+ |
| HA/мультиарендность | да (object storage + RRU EE) | нет | да (VL-cluster, vlagent) |
| K8s | паттерн chart+operator | ECK-operator | паттерн chart+operator |
| Плюшина | memcached-extstore для крупных | ILM, audit logs, SLO-alerts, SIEM | low RAM/disk, zero-config single binary |

## 6. Grafana

### 6.1 Что это и чего она не делает

| Делает | Не делает |
|---|---|
| дашборды, explore, ad-hoc запросы | не хранит метрики и логи |
| единый UI над VM, Prometheus, Mimir, Loki, Tempo, Pyroscope, Elasticsearch, SQL | не собирает данные (нужен агент/collector) |
| unified alerting, правила по нескольким источникам | не заменяет Alertmanager (хотя умеет contact points) |
| provisioning дашбордов/datasource'ов как код | не даёт RBAC на уровне данных (серверного) |
| generic OAuth2/OIDC в OSS | SAML и LDAP — только Enterprise и Cloud |

### 6.2 Ресурсы по официальной модели

[installation](https://grafana.com/docs/grafana/latest/setup-grafana/installation/):

| Тир | Пользователи | Правила | Datasource'ы | Дашборды | CPU | RAM |
|---|---|---|---|---|---|---|
| Минимум | — | — | — | — | 1 ядро | 512 МБ |
| Small | <25 | <100 | <5 | <200 | 2 ядра | 2–4 ГБ |
| Medium | 25–200 | 100–1000 | 5–25 | 200–2000 | 4–8 ядер | 8–16 ГБ |
| Large | 200+ | 1000+ | 25+ | 2000+ | 8–16+ ядер | 16–32+ ГБ |

Память: зависит от объёма запросов, алертов, дашбордов; рендерер ~1 ГБ на воркер;
OSS: движок алертинга в том же процессе, что UI (Large лучше выносить на отдельный
инстанс); пользователи >1000 + интервалы <1 минута — выделенный инстанс.

### 6.3 Enterprise (платный)

SAML, LDAP (в OSS — только OAuth2/OIDC и basic auth), Team Sync, доступ к
kubernetes/elastic API, готовые дашборды для многих datasource'ов, oncall-дежурства,
quota, query caching. Осторожно: Team Sync и OAuth-team-sync сейчас — EE.

## 7. Профили эксплуатации: хоумлаб и энтерпрайб

### 7.1 Матрица профилей

| Параметр | Хоумлаб-масштаб | Энтерпрайб (типовой кластер) |
|---|---|---|
| Active series | 10³–10⁵ | 10⁵–10⁷ |
| Logs/день | 1–50 ГБ | 1–100 ТБ |
| HA | 1 нода, реплики | серверный HA, несколько нод |
| Мультиарендность | один тенант | RRU в Mimir, vmalert multitenant |
| Кардинальность | низкая/средняя | высокая, надо точить |
| Compliance | фиксируется | SOC2/ISO, GDPR, аудиты |
| Операционная сложность | минимизируем | допустима |
| Бюджет | минимизируем | оправдан |

### 7.2 Что важно в крупных

- **Mimir — единственная «из коробки» мультиарендная платформа** (десятки
  млн серий, слабые tenant-лимиты, per-tenant API, RRU).
- **Tempo** — работает как S3-хранилище и как бэкенд для OTel-трейсов;
  TraceQL в браузере.
- **Zabbix** — лучше с SNMP-парком (молчаливый инструмент: что не сломано, не
  видно), а не метриками Prometheus.
- **ELK** — если есть SIEM/forensics или нативный поиск по неструктурированным
  логам критичен; платить за это временем на ops и диском.

## 8. Стеки целиком

### 8.1 VictoriaMetrics (похож на LGTM)

```
exporters ──pull──▶ vmagent ──remote write──▶ VictoriaMetrics ◀──OTLP── Alloy
                                                   │
                                     vmalert ──▶ Alertmanager ──▶ webhook
                                                   │
                                               Grafana (OIDC, если нужен)
```

Компоненты: vmagent + VictoriaMetrics + vmalert (+ Alertmanager) + Grafana.
Логи — Loki или VictoriaLogs, трейсы — Tempo или VictoriaTraces.
Плюсы: официальные compose-файлы, Helm-чарты (`victoria-metrics-single`,
`victoria-metrics-k8s-stack`), CRD `VMServiceScrape`/`VMRule`, единственный
vendor на метрики + логи + трейсы + мониторинг. Минусы: экосистема ниже
Prometheus-мира; downsampling/multi-retention — Enterprise; техподдержка отдельная.

### 8.2 Классика: Prometheus-стек

kube-prometheus-stack: Operator + Prometheus + Alertmanager + node-exporter +
kube-state-metrics + Grafana, цели — через ServiceMonitor. Логи — Loki
(HA или RRU) или Prometheus-стек не отдаёт логи (возможно — через Loki);
трейсы — Tempo. Плюсы: эталон, максимум примеров/дашбордов. Минусы: выше RAM
на кардинальность, нет официального compose, история — только локальный диск
(переходите на remote_write в Mimir/VM или Thanos sidecar).

### 8.3 Zabbix

Сервер + прокси (для распределённых) + БД + фронтенд. Плюсы:
агенты под всё, SNMP/IPMI/JMX, LLD, шаблоны, зрелые эскалации. Минусы:
«всё в одной коробке» — по таблице §3.4 есть дорогие и непривативные паблик.

### 8.4 ELK/OpenSearch

Elasticsearch + Kibana + beats (Filebeat/Metricbeat). Плюсы: самый сильный
полнотекстовый поиск, SIEM, готовые интеграции, ILM, enterprise-алертинг.
Минусы: дорого по RAM/диску/операциям; лицензионная неопределённость (Elastic).
OpenSearch — дешевле и с сильной SSO (см. §5.4), но сильно похож на ES.

## 9. Как выбирать

| Сценарий | Метрики | Логи | UI |
|---|---|---|---|
| Один узел, до ~1 млн серий, до ~20–50 ГБ логов/день | VictoriaMetrics single-node | Loki (HA-монолит) или VictoriaLogs | Grafana |
| Несколько кластеров/тенантов, десятки млн серий | Mimir или VictoriaMetrics cluster | Loki microservices | Grafana |
| Уже есть парк Prometheus, нужна только история | Thanos sidecar или remote_write в VM/Mimir | — | Grafana |
| Сетевое железо, SNMP, инвентарь, «высокий энтерпрайз» | Zabbix (+ Prometheus-эндпоинты через HTTP agent) | Zabbix/отдельно | Zabbix frontend |
| Полнотекстовый поиск, SIEM, аудит логов | — | Elasticsearch/OpenSearch | Kibana |
| Нужен только аптайм | — | — | Uptime Kuma/Gatus + алерты |

Типичные ошибки:

- **Mimir/Thanos «на вырост» для одного узла** — сложность и RAM станут реальными расходами сегодня.
- **Считать Grafana хранилищем.**
- **Zabbix и Prometheus одновременно без согласованности источников истины.**
- **Elasticsearch для логов «потому что искали по тексту»**, когда фильтр по сервису — в 95%.
- **Игнорировать кардинальность.**

## 10. Альтернативы и закрытые SaaS

### 10.1 Классические «агент + сервер»

| Система | Сильная сторона | Лицензия | K8s | SSO |
|---|---|---|---|---|
| Zabbix 8.0 | агенты, SNMP, IPMI, JMX, шаблоны, HA сервера | AGPL-3.0 | офиц. Helm | SAML+LDAP+MFA, OIDC нет |
| Checkmk Raw | ~2000 плагинов, автообнаружение сервисов | GPL-2.0 | Helm | SAML+LDAP |
| Icinga 2 | config-as-code, распределённые зоны | GPL-3.0 | community | LDAP; SAML модулями |
| Nagios Core | легаси-стандарт | GPL-2.0 | нет | нет |
| LibreNMS | SNMP-автообнаружение сетевого железа | GPL-3.0 | community | LDAP/HTTP |

### 10.2 Реалтайм и лёгкие

- **Netdata 2.13** (GPL-3.0) — посекундные метрики на узел, ML-аномалии,
  parent/child; отдаёт данные в Prometheus remote write; SSO — только
  Netdata Cloud.
- **Glances**, **btop** — ad-hoc осмотр без истории и алертинга.

### 10.3 Аптайм-пробы

Uptime Kuma 2.x (MIT, ~90 каналов, UI-конфиг, OIDC нет), Gatus (Apache-2.0,
config-as-code, OIDC есть), Healthchecks (BSD, heartbeat для cron/бэкапов),
Upptime (GitHub Actions). Оправдания выбора — в observability-standards.md §6.

### 10.4 APM, ошибки, all-in-one

| Система | Что это | Лицензия | SSO |
|---|---|---|---|
| Sentry self-hosted | ошибки + трейсы + replay; минимум 4 CPU/16 ГБ RAM | FSL-1.1-Apache-2.0 (не OSI) | DIY |
| GlitchTip | лёгкий Sentry-совместимый | MIT | OIDC/SAML |
| SigNoz | APM+логи+метрики на ClickHouse, OTel-native | MIT core, EE отдельно | EE |
| OpenObserve | Rust single-binary: логи+метрики+трейсы на S3 | AGPL-3.0 | OIDC/LDAP |
| HyperDX | логи+трейсы на ClickHouse | MIT | — |

ClickHouse-стеки (SigNoz, OpenObserve, HyperDX) — дорого по памяти и диску
(отдельный CH), но дают скорость SQL-запросов их хисторических данных.

### 10.5 Закрытые SaaS (для контраста)

Datadog (Prometheus-скрейпы, OTLP, Fluent Bit, SAML), New Relic (OTLP, free
tier 100 ГБ/мес), Dynatrace (OTLP), Splunk (HEC, куплен Cisco в 2025), Sumo
Logic, Better Stack, Grafana Cloud (managed-версия всего стека выше). Гибридный
паттерн для «послушных» данных: локально + зеркало от Alloy/Collector.

## 11. SSO-матрица

| Компонент | Нативный OIDC | Как подключить к IdP |
|---|---|---|
| Grafana | ✅ generic OAuth: discovery, PKCE, JWKS, role_attribute_path; Team Sync — EE | напрямую |
| Gatus | ✅ OIDC/OAuth2 | напрямую |
| Beszel | ✅ OAuth2 + custom OIDC | напрямую |
| Dozzle | ✅ OIDC | напрямую |
| Uptime Kuma | ❌ | oauth2-proxy / forward-auth |
| Prometheus / Alertmanager / Pushgateway | ❌ | oauth2-proxy / basic-auth за прокси |
| VictoriaMetrics / vmalert | ❌ | vmauth + официальный OIDC-гайд |
| Loki / Tempo / Mimir (OSS) | ❌ | доступ через Grafana или прокси |
| Zabbix | ❌ (только SAML) | SAML-мост (Keycloak/Authentik) либо forward-auth |
| OpenSearch | ✅ бесплатно | напрямую |
| Graylog | ✅ | напрямую |
| GlitchTip | ✅ | напрямую |
| OpenObserve | ✅ | напрямую |
| Sentry self-hosted | ⚠️ DIY (sentry.conf.py) | сложно |

Практический вывод: **Grafana — единственная UI-точка входа с OIDC в OSS**;
«голые» компоненты — за ней или за oauth2-proxy/vmauth.

## 12. Первоисточники

- Prometheus: [overview](https://prometheus.io/docs/introduction/overview/),
  [storage](https://prometheus.io/docs/prometheus/latest/storage/),
  [FAQ](https://prometheus.io/docs/introduction/faq/),
  [security model](https://prometheus.io/docs/operating/security/),
  [HA](https://prometheus.io/docs/alerting/latest/high_availability/),
  [v3.16.0](https://github.com/prometheus/prometheus/releases/tag/v3.16.0).
- VictoriaMetrics:
  [single-node](https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/),
  [sizing guide](https://docs.victoriametrics.com/guides/understand-your-setup-size/),
  [cluster](https://docs.victoriametrics.com/victoriametrics/cluster-victoriametrics/),
  [enterprise](https://docs.victoriametrics.com/victoriametrics/enterprise/),
  [v1.156.0](https://github.com/VictoriaMetrics/VictoriaMetrics/releases/tag/v1.156.0).
- Grafana: [installation/hardware](https://grafana.com/docs/grafana/latest/setup-grafana/installation/),
  [generic OAuth](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-authentication/generic-oauth/),
  [SAML](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-authentication/saml/),
  [v13.3.1](https://github.com/grafana/grafana/releases/tag/v13.3.1).
- Loki/Tempo/Mimir:
  [deployment modes](https://grafana.com/docs/loki/latest/get-started/deployment-modes/),
  [size the cluster](https://grafana.com/docs/loki/latest/setup/size/),
  [Mimir capacity planning](https://grafana.com/docs/mimir/latest/manage/run-production-environment/planning-capacity/),
  [v3.7.10](https://github.com/grafana/loki/releases/tag/v3.7.10),
  [v3.1.1](https://github.com/grafana/tempo/releases/tag/v3.1.1),
  [mimir-3.2.6](https://github.com/grafana/mimir/releases/tag/mimir-3.2.6).
- Zabbix: [requirements](https://www.zabbix.com/documentation/current/en/manual/installation/requirements),
  [authentication](https://www.zabbix.com/documentation/current/en/manual/web_interface/frontend_sections/users/authentication),
  [8.0 LTS](https://www.zabbix.com/rn/rn8.0.0).
- Elastic: [JVM settings](https://www.elastic.co/docs/reference/elasticsearch/jvm-settings),
  [size your shards](https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/size-shards),
  [Kibana memory](https://www.elastic.co/docs/deploy-manage/production-guidance/kibana-configure-memory),
  [LICENSE.txt](https://github.com/elastic/elasticsearch/blob/main/LICENSE.txt),
  [v9.5.6](https://github.com/elastic/elasticsearch/releases/tag/v9.5.6).
- OpenTelemetry: [OTLP](https://opentelemetry.io/docs/specs/otlp/),
  [Collector v0.165.0](https://github.com/open-telemetry/opentelemetry-collector-releases/releases/tag/v0.165.0),
  [Alloy v1.22.0](https://github.com/grafana/alloy/releases/tag/v1.22.0).
- VictoriaLogs: [docs](https://docs.victoriametrics.com/victorialogs/),
  [v1.54.0](https://github.com/VictoriaMetrics/VictoriaLogs/releases/tag/v1.54.0).
- OpenSearch: [3.10.0](https://github.com/opensearch-project/OpenSearch/releases/tag/3.10.0),
  [OIDC docs](https://docs.opensearch.org/latest/security/authentication-backends/openid-connect/).
