# Pyroscope

Хранилище непрерывных профилей (continuous profiling). Заполняет третий столп
наблюдаемости: метрики (VictoriaMetrics), логи (Loki), трейсы (Tempo) и
профили (Pyroscope).

## Зачем

Метрики показывают «что-то стало медленно», логи — «что произошло», трейсы —
«где именно в цепочке запроса». Профиль отвечает на другой вопрос: **какой код
этого процесса жёг CPU**, с функциями и исходными строками.

## Откуда берутся данные

Из `clusters/casa/apps/alloy-profiler` — отдельного Alloy в режиме eBPF-сэмплирования.
Он сэмплирует стеки процессов в контейнерах той же ноды и шлёт их сюда.

Push через OTel/SDK тоже возможен, но требует инструментации в приложении —
для third-party образов (Synapse, LiveKit, nextcloud, immich) неприменимо.

## Почему отдельный Alloy

Действующий `clusters/casa/apps/alloy` намеренно работает без root и eBPF-возможностей
(`runAsNonRoot`, `drop: ["ALL"]`, без hostPath) — это зафиксировано в его
README как решение: он читает логи всех подов, и компрометация там хуже всего.
eBPF-профилирование требует root и CAP_SYS_ADMIN, поэтому вынесено отдельно.

### Пути на диске

Пять путей Pyroscope на диске, и все пять по умолчанию относительные — от
рабочего каталога контейнера, который равен `/`. Первые три заданы в
`config/pyroscope.yaml`, последние два — флагами в `k8s/deployment.yaml`,
потому что их YAML-ключей в 2.3.1 нет, а парсер конфига на неизвестном ключе
падает. Разбор и точная ошибка — в комментарии к `config/pyroscope.yaml`.

Недозаданный путь выглядит как `permission denied` в `mkdir` и валит весь
процесс, а не только модуль:

```sh
kubectl -n monitoring logs deploy/pyroscope --tail=-1 | grep "module failed"
kubectl -n monitoring get pod -l app=pyroscope
```

`--tail=-1` здесь обязателен: без него `kubectl logs` отдаёт последние 10
строк, а это ровно хвост с ошибкой — кажется, что процесс ничего не писал.

### Профили не скрейпятся

vmagent не имеет job'а `pyroscope` в `clusters/casa/apps/victoria-metrics/config/vmagent/scrape.yml`,
поэтому метрик у сервиса нет и в VM не попадает. Пока это так, ориентироваться
надо на состояние пода и логи, а не на дашборд.

## Связка с трейсами

`/sys/fs/bpf` смонтирован в **оба** компонента (Beyla и alloy-profiler) с
`mountPropagation: HostToContainer` — pinned BPF-карты должны быть одни и те
же. Без этого Beyla пишет в логи `OBI will use process-internal maps`, и
переход «трейс → профиль» не работает.

В Grafana: datasource Pyroscope умеет искать спаны по `service.name` профиля
(настроено в `clusters/casa/apps/grafana/config/datasources.yaml`, `tracesToProfiles`).

## Цена

- **CPU:** ~1–2% на ядро непрерывно, пока работает сэмплирование.
- **Диск:** PVC 10 Gi. Pyroscope сам удаляет старые блоки при нехватке места
  (`retention-policy-*`), плюс `limits.retention_period: 168h`.
- **Привилегии:** компонент с eBPF-доступом (второй после Beyla). Взят набор
  capabilities, а не `privileged: true`.
- **Символизация:** у чужих образов нет debug-символов, часть стеков будет без
  имён функций. Go-бинари обычно резолвятся по встроенной pclntab.

## Проверка

```sh
kubectl -n monitoring get pods -l app=pyroscope
kubectl -n monitoring logs -l app=alloy-profiler --tail=20
# в Grafana: Explore → Pyroscope → profiler → процесс
```

## Ограничения

- Нет высокого разрешения исходников: адреса и имена функций, но не файлы.
- eBPF-сэмплирование — по таймеру, короткие всплески CPU могут не попасть
  в выборку.
- `BPF_PROG_TYPE_PERF_EVENT` требует kernel ≥ 4.9 (на узле 7.2.7).
