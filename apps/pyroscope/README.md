# Pyroscope

Хранилище непрерывных профилей (continuous profiling). Заполняет третий столп
наблюдаемости: метрики (VictoriaMetrics), логи (Loki), трейсы (Tempo) и
профили (Pyroscope).

## Зачем

Метрики показывают «что-то стало медленно», логи — «что произошло», трейсы —
«где именно в цепочке запроса». Профиль отвечает на другой вопрос: **какой код
этого процесса жёг CPU**, с функциями и исходными строками.

## Откуда берутся данные

Из `apps/alloy-profiler` — отдельного Alloy в режиме eBPF-сэмплирования.
Он сэмплирует стеки процессов в контейнерах той же ноды и шлёт их сюда.

Push через OTel/SDK тоже возможен, но требует инструментации в приложении —
для third-party образов (Synapse, LiveKit, nextcloud, immich) неприменимо.

## Почему отдельный Alloy

Действующий `apps/alloy` намеренно работает без root и eBPF-возможностей
(`runAsNonRoot`, `drop: ["ALL"]`, без hostPath) — это зафиксировано в его
README как решение: он читает логи всех подов, и компрометация там хуже всего.
eBPF-профилирование требует root и CAP_SYS_ADMIN, поэтому вынесено отдельно.

## Развёртывание

```sh
kubectl apply -k apps/pyroscope
kubectl apply -k apps/alloy-profiler
```

## Связка с трейсами

`/sys/fs/bpf` смонтирован в **оба** компонента (Beyla и alloy-profiler) с
`mountPropagation: HostToContainer` — pinned BPF-карты должны быть одни и те
же. Без этого Beyla пишет в логи `OBI will use process-internal maps`, и
переход «трейс → профиль» не работает.

В Grafana: datasource Pyroscope умеет искать спаны по `service.name` профиля
(настроено в `apps/grafana/config/datasources.yaml`, `tracesToProfiles`).

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
