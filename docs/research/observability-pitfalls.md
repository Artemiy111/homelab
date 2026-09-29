# Грабли при настройке observability

Практические выводы из настройки стека. Каждый пункт — реально случившаяся
ошибка, а не теория. Проверяй здесь, прежде чем менять конфиги Tempo, Loki,
Beyla, Pyroscope, nginx или Alloy.

Общий принцип: **сначала валидируй конфиг изолированно, потом деплой**.
Все пункты ниже найдены либо валидатором, либо падением пода на стенде.

## Tempo 3.x: секции `compactor` больше нет

В Tempo 2.x удаление трейсов делал top-level блок `compactor`. В **3.0.3 его
нет** — архитектура заменена на backend scheduler и backend worker:

```
field compactor not found in type app.Config
```

Retention теперь задаётся так:

```yaml
storage:
  trace:
    blocklist_poll: 5m
backend_scheduler:
  provider:
    retention:
      interval: 1h
    compaction:
      compaction:
        block_retention: 168h
        compacted_block_retention: 1h
```

`compactor.compaction.block_retention` из документации Tempo 2.x приводит к
падению пода. Без `blocklist_poll` планировщик не узнаёт об устаревших
блоках.

**Проверка до деплоя:**

```sh
kubectl run tempo-verify --image=<tempo> --restart=Never --overrides=... \
  --command -- /tempo -config.file=/etc/tempo/tempo.yaml -config.verify=true
# Succeeded = валидно. Обязателен контрольный тест: сломанный конфиг должен
# дать Failed, иначе вывод «Succeeded» ничего не доказывает.
```

## Tempo и Loki: retention не работает сам по себе

- Tempo: без `blocklist_poll` + `block_retention` данные не удаляются **никогда**.
- Loki: `retention_period` работает только с `compactor.retention_enabled: true`.

В обоих случаях PVC конечен, и без retention он просто переполняется.

## Pyroscope: три пути на диске по умолчанию относительные

В v2 три пути дефолтят в `./data/v2/...`. Рабочий каталог контейнера — `/`,
он read-only, и Pyroscope падает:

```
metastore: failed to initialize store: db dir: mkdir ./data/v2: permission denied
```

Задавать нужно все три явно, иначе ошибка вылезет по одному:

```yaml
storage:
  filesystem:
    dir: /var/lib/pyroscope/shared
metastore:
  data_dir: /var/lib/pyroscope/metastore/data
  raft:
    dir: /var/lib/pyroscope/metastore/raft
    snapshots_dir: /var/lib/pyroscope/metastore/raft
```

Две ловушки в этом блоке:

- `snapshots_dir` **есть** в `-help`, но **отсутствует** в
  reference-configuration-parameters. Надо смотреть `-help` бинарника.
- YAML-ключи используют **подчёркивания** (`snapshots_dir`, `data_dir`,
  `bootstrap_peers`), хотя CLI-флаги — дефисы. С дефисом получаешь
  `field snapshots-dir not found in type raftnode.Config`.

Retention: `limits.retention_period` (дефолт 31d). Поле
`compactor.compactor_blocks_retention_period` — **только для v1 storage**, в v2
не работает.

## Beyla: health-эндпоинт всегда на loopback

Документация предлагает `health_check.listen_address: 0.0.0.0`, и
`BEYLA_HEALTH_CHECK_LISTEN_ADDRESS`, но в 3.37.0 это не работает:
`pkg/components/beyla.go` вызывает `health.ListenAndServe`, который жёстко
использует `127.0.0.1`. Ключ просто не подключён (upstream-пробел).

Любая kubectl-проба по адресу получает `connection refused`. Официальный чарт
Beyla проб тоже не имеет — пошли следом и задокументировал причину.

## Внутренние метрики Beyla: не `/metrics` и слушают все интерфейсы

- Endpoint — `/internal/metrics`, а не `/metrics` (404 на `/metrics`).
- Порт задаётся `BEYLA_INTERNAL_METRICS_PROMETHEUS_PORT` и вешается на
  `:8999` (все интерфейсы, в отличие от health-эндпоинта) — скрейп с других
  подов работает.

## nginx: две ловушки с логами

**1. Несколько `access_log` на одном уровне накапливаются.** Если добавить свою
директиву рядом с унаследованной, каждое событие уйдёт в лог дважды. Именно
так выглядели «дубли» в Loki.

**2. Дублировать имя `log_format` нельзя:**

```
emerg: duplicate "log_format" name "main"
```

Под уходит в CrashLoop, а старый продолжает писать — выглядит как «формат не
применился». Правильно: **взять `nginx.conf` под управление целиком** (через
ConfigMap с `subPath` на `/etc/nginx/nginx.conf`) и задать один `access_log` с
уникальным именем формата. `include /etc/nginx/conf.d/*.conf` в нём оставить —
server-блок образа нужен.

**Проверка до деплоя:** собрать префикс с кандидатом и прогнать `nginx -t`.

## Kubernetes: имя порта не длиннее 15 символов

`ports[0].name: must be no more than 15 characters`. Ошибка от `kubectl apply`
видна сразу, но стоит лишнего цикла.

## ConfigMap через `subPath` не обновляется в живом поде

Монтирование файла из ConfigMap через `subPath` **не подхватывает** изменения
ConfigMap: под надо пересоздавать. Правка конфига без `rollout restart`
молча ничего не делает. Kustomize-оверлей с хэшем в имени ConfigMap решает
это для Deployment/DaemonSet, потому что меняет pod template.

## Alloy: `discovery.kubernetes` требует `role` дважды

`role` обязателен **и** на верхнем уровне блока, **и** внутри `selectors`:

```river
discovery.kubernetes "local_pods" {
  role = "pod"           # иначе "missing required attribute \"role\""
  selectors {
    role  = "pod"
    field = "spec.nodeName=" + sys.env("NODE_NAME")
  }
}
```

`NODE_NAME` должен идти от `fieldRef: spec.nodeName`, а не от
`metadata.name`: фильтр сравнивается с именем **ноды**. С `metadata.name`
селектор просто ничего не найдёт — без ошибки.

**Валидация конфига Alloy:**

```sh
alloy validate /etc/alloy/config.alloy
```

Подкоманда есть (`alloy validate`). `alloy fmt --verify` **не существует** —
`unknown flag: --verify`.

## eBPF: список capabilities неполон

Одного `CAP_BPF`/`CAP_PERFMON`/`CAP_SYS_ADMIN` мало. Что реально требуется по
мере наступления:

| Capability | Зачем, симптом без неё |
| --- | --- |
| `CAP_SYS_ADMIN` | uprobe'ы, стек процессов |
| `CAP_PERFMON` | `perf_event_open`, загрузка BPF-программ |
| `CAP_SYSLOG` | `failed to read kernel symbols: unable to read kallsyms addresses` |
| `CAP_SYS_RESOURCE` | `failed to adjust rlimit: operation not permitted` |
| `CAP_SYS_PTRACE` | доступ к `/proc/<pid>` и namespace'ам |
| `CAP_DAC_READ_SEARCH` | чтение ELF |
| `CAP_CHECKPOINT_RESTORE` | открытие ELF |
| `CAP_NET_RAW` | сокет-фильтры |

`CAP_SYS_RESOURCE` в официальном примере Alloy закомментирован как
«pre 5.11 only», но на ядре 7.2.7 он всё ещё нужен.

## bpffs нужен обоим eBPF-компонентам

Beyla пишет `OBI will use process-internal maps`, пока `/sys/fs/bpf` не
примонтирован. Pinned BPF-карты должны быть **общими** у Beyla и
alloy-profiler, иначе связка «трейс → профиль» не работает. Монтировать с
`mountPropagation: HostToContainer`.

## Kustomize не удаляет старые ConfigMap

Каждая правка конфига создаёт новый `*-<hash>`, старые остаются лежать. Со
временем в кластере копится мусор (`vmagent-scrape-*`, `grafana-alerting-*`).
При выборе ConfigMap для проверки всегда сверяйся с тем, на который реально
ссылается Deployment, а не с первым попавшимся `kubectl get cm`.

## VictoriaMetrics: `minFreeDiskSpaceBytes` ничего не удаляет

Флаг означает «ниже порога storage **перестаёт принимать новые данные**», и
дефолт у него 100 МБ — то есть срабатывал бы неявно. В single-node
перенаправлять данные некуда, поэтому старые данные **не вытесняются**: это
не «мягкая деградация», а остановка сбора метрик. Реальное решение — место на
диске плюс согласованный с ним `retentionPeriod`.

## Grafana: файлы алертов и неизвестные опции

- Провижинер Grafana при чтении смонтированного ConfigMap ругается на
  `..data` и `..<timestamp>` (`file has invalid suffix ... skipping`) — это
  артефакт Kubernetes, файлы при этом читаются.
- Неизвестные опции конфига **молча игнорируются**: `admin_users` в Synapse
  не существует, и Synapse стартовал как ни в чём не бывало. Проверять
  фактическое поведение, а не «опцию поставил и жду».

## Beyla: отсутствие трейсов не значит «не инструментировано»

Beyla создаёт span только на **наблюдаемом входящем запросе**. Если к сервису
никто не обращался, трейсов не будет — при этом процесс уже инструментирован.
Вывод «Beyla не работает» по пустому Tempo делается легко и ошибочно.

Правильная проверка после расширения списка namespace'ов:

1. Убедиться, что новый ConfigMap смонтирован, а в нём ожидаемое число
   `k8s_namespace` — иначе проверяешь старый под.
2. Сгенерировать трафик: один `kubectl exec` с циклом внутри контейнера, а не
   `exec` на каждый сервис (на каждый вызов уходит несколько секунд, проверка
   не укладывается в таймаут).
3. Смотреть Tempo по полю **`rootServiceName`**, а не `serviceName`:
   `/api/search?limit=200&start=<unix>&end=<unix>`. Второе поле в ответе
   отсутствует, и запрос молча выглядит «пустым».
4. Ориентироваться на сервисы **без нативной OTel-инструментации** — они
   доказывают, что работает именно eBPF. `paperless`, `nextcloud-exporter`,
   `jitsi-web` в Tempo появились только благодаря Beyla.

## Проверка ConfigMap: сверяйся с хэшем, а не с именем

`kubectl get cm | grep beyla` покажет **все** когда-либо созданные ConfigMap —
Kustomize не удаляет старые. Один и тот же конфиг живёт под несколькими именами
(`beyla-config-2g5646tff4`, `beyla-config-m6fchm55b7`, `beyla-config-gh2tgmkk6k`).
Номер совпадений в **одном** из них ничего не значит, пока не проверил, какой
ConfigMap указан в `Deployment`/`DaemonSet`.

Полезная проверка — идти по ссылке, а не по имени:

```sh
kubectl -n monitoring get cm <имя> -o go-template='{{index .data "beyla.yml"}}' | grep -c k8s_namespace
```

Плюс две ловушки проверки:

- В контейнере Beyla **нет `grep`** (distroless) — `kubectl exec ... grep`
  падает с `executable file not found in $PATH`. Читать ConfigMap через API.
- Перед `kubectl apply -k` на сервере нужен `git pull`: под руками лежит
  рабочая копия, и apply применяет **устаревший** манифест, рапортуя
  `configmap ... unchanged`.

## Alloy `pyroscope.ebpf`: других типов профилей не бывает

У компонента **нет аргумента `profiler_type`**. Он умеет ровно одно —
сэмплировать стеки по CPU, поэтому `process_cpu` — единственный тип, который он
способен отдать. Типы `memory`, `block`, `mutex`, `goroutine` — это
SDK-профилирование внутри приложений, непрерывный eBPF-сэмплинг их не даёт.

Единственный переключатель типа данных в компоненте — `off_cpu_threshold`
(по умолчанию `0`, выключено). Он добавляет off-CPU профили: кто и сколько
времени не делал ничего, ожидая блокировок и ввода-вывода.

Описание аргумента противоречиво: называется `threshold` (похоже на
длительность), но текст говорит «probability from 0 to 1». Значение
проясняется только в логах при старте:

```
Enabled off-cpu profiling with p=0.100000
```

То есть это вероятность, а не микросекунды. Проверять приходится
эмпирически.

## Alloy `pyroscope.ebpf`: имена сервисов по умолчанию — `ebpf/<ns>/<container>`

Без `discovery.relabel` компонент выводит `service_name` сам, в формате
`ebpf/<namespace>/<container_name>`. В интерфейсе это читается как «группа
eBPF» с невнятными именами вроде `ebpf/nextcloud/nextcloud`.

## eBPF-профайлер не умеет символизировать Go 1.27

Ошибка в логах, не фатальная, но профили останутся без имён функций:

```
Failed to load /usr/bin/mariadb-operator: unsupported Go version go1.27.1
(need >= 1.13 and <= 1.26)
```

Аналогично падает символизация Ruby (`unable to read 'ruby_version'`) и
конвертация .NET-метаданных (`bad magic number ... in System.Reflection.Metadata.dll`).
Если сервис собран новее поддерживаемого Go, в flame graph увидишь адреса и
имена модулей вместо функций — это не поломка пайплайна.

## `kubectl top`: колонки NAME CPU MEMORY — легко перепутать

`kubectl top pods --no-headers` даёт три поля: `$1` имя, `$2` CPU, `$3`
память. Ошибка в awk (`$3` в слот для cpu) даёт правдоподобные числа с
суффиксом `Mi` и вкратце венчает оценку стоимости в несколько раз. Особенно
коварно, что при росте кластера колонки съезжают по ширине имени.

Проверять дорого стоящие eBPF-компоненты надо с правильными колонками: цена
наблюдаемости — это ровно то, что решает, оставлять ли её включённой.

## OTel `spanmetrics`: имя измерения — с точкой, а не с подчёркиванием

`exclude_dimensions` работает по именам из набора по умолчанию, а в нём
**точки**: `span.name`, `service.name`, `span.kind`, `status.code`,
`collector.instance.id`. Подчёркивание — это уже имя лейбла *после* конвертации
в Prometheus.

Написав `exclude_dimensions: [span_name]`, получаешь работающий пайплайн, который
молча ничего не делает:

```sh
# НЕ работает: span_name — это уже имя лейбла, не имя измерения
exclude_dimensions: [span_name]

# Работает
exclude_dimensions: [span.name, collector.instance.id]
```

`otelcol validate` такой конфиг **принимает без ошибки** (проверено контрольным
тестом). Единственный способ узнать, сработало ли, — посмотреть реальные лейблы
в VictoriaMetrics. Проверка: было 218 разных `span_name`, стало 1.

Настраивать кардинальность дешевле, чем чинить её потом:

- `aggregation_cardinality_limit` (дефолт `0`, то есть ограничения нет) —
  предохранитель: после N комбинаций новые отбрасываются с
  `otel.metric.overflow="true"`.
- `series_expiration` — подчищает осиротевшие комбинации от bursty-нагрузки.
- Компонент переименован в `span_metrics`; `spanmetrics` deprecated.

## Отдельный экспортёр для span-метрик — не паранойя, а необходимость

У существующего экспортёра `prometheus` стоит
`resource_constant_labels: included: ["*"]`, и он отдаёт метрики **всех**
пайплайнов. Span-метрики, попав в него, получают каждый resource-атрибут трейса
(`service.instance.id`, `k8s.pod.uid`) в качестве лейбла — кардинальность
размножается на число подов. Отдельный экспортёр на отдельном порту
(`prometheus/spanmetrics` на 8890) без `resource_constant_labels` даёт
1 МБ вместо 20 МБ и ограничивает урон.

## vmagent: `maxScrapeSize` по умолчанию 16 МБ — это ловушка

Гистограммы Beyla (`http_client`, `http_server`, `db_client`, `db_server`,
`go_schedule`, `go_memory`) дают на `/metrics` коллектора **55 МБ** — и это
без span-метрик. Дефолт vmagent в 16 МБ не рассчитан на такой стек, и джоба
падает целиком:

```
cannot scrape target ... exceeds -promscrape.maxScrapeSize (16777216 bytes)
```

Опаснее всего, что это молчит: алерт `scrape-target-down` не заметил упавшую
джобу, потому что она стояла последней в списке `scrape_configs`. Добавил
span-метрики — стало 76 МБ, и диагностика ушла по ложному следу: «виноваты
span-метрики». На самом деле джоба была битая и до этого.

Что делать: `max_scrape_size: 100MB` в конфиге джобы явно. И не делать выводов
о виновнике по тому, что изменилось последним, — проверять, работала ли джоба
до этого (`up{job="..."} == 0` по истории).

## Grafana Unified Alerting: условие `gt 0` требует положительных значений

Цепочка правила `A (запрос) -> B (reduce) -> C (threshold: gt 0)` разворачивает
«вернулась серия» в решение «Alerting». Отсюда три требования, каждое из
которых нарушается молча:

1. **Выражение должно возвращать положительные значения.** Наивное
   `predict_linear(...[1d], 3*86400) < 0` возвращает отрицательные числа, и
   `gt 0` не выполняется **никогда**: правило мертво и при этом числится
   здоровым. Нужен `< bool 0`, который даёт 1/0.
2. **Редьюсер `last` годится только для одного таргета.** Правило на все PVC
   возвращает вектор, `last` схлопывает его по произвольной серии: сработает,
   когда нужный том дал 0, и промолчит, когда он дал 1. Нужен `max`.
3. **Оператор `and` берёт значения ЛЕВОГО операнда.** Если слева стоит
   `certmanager_certificate_expiration_timestamp_seconds > 0` (без `bool`),
   правило отдаст сырые таймстемпы вида `1.9e9`, порог `gt 0` пройдёт всегда, и
   алерт будет висеть сработавшим постоянно. С `< bool` нужно ставить
   операнды так, чтобы слева оказался 1/0.

Правило нельзя признать рабочим по факту загрузки в Grafana. Обязательна
проверка выражения в VictoriaMetrics, и обязателен **контрольный тест**:
подставить заведомо ложный порог (например `< bool 99999 * 86400`) и убедиться,
что правило возвращает 1 — иначе неизвестно, срабатывает ли оно вообще.

## Ручной перечень томов не масштабируется

Было 5 правил, выписанных руками под диски стенки (`loki-data < 2e9`,
`tempo-data < 1e9`, `pyroscope-data < 2e9` и т.д.). Томов в кластере 62, и
правил про `dawarich-db` не существовало — инцидент #0001 система не могла
заметить. Один generic-алерт с `predict_linear` по всем PVC заменяет весь
перечень, и новое приложение сразу под защитой.

Порог ёмкости (5 ГиБ) обязателен: без него в правило попадают мелкие служебные
тома, для которых 15% — это несколько мегабайт, и алерт превращается в шум.

## Порядок работы, который себя оправдал

1. Найти источник правды: `-help` бинарника, reference-доки **той же версии**,
   исходники в тегах. Не память и не доки соседней мажорной версии.
2. Провалидировать конфиг изолированным подом.
3. Контрольный тест: сломанный вариант обязан упасть, иначе проверка ничего
   не доказывает.
4. Деплоить по одному компоненту, проверяя поды и логи.
5. Читать фактическое состояние из рантайма (`/flags`, `/config`), а не из
   применённого манифеста.
