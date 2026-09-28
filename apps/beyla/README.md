# Beyla

eBPF-автоинструментация: трейсы и RED-метрики сервисов namespace `element`
(Synapse, LiveKit, coturn, lk-jwt-service) без изменений в приложениях.

Зачем: ни один из компонентов Element не умеет отдавать трейсы сам.
Synapse поддерживает только legacy Opentracing (Jaeger), у LiveKit SFU нет
секции `otel`, coturn и lk-jwt-service OTel не поддерживают. Beyla снимает
данные eBPF-пробами на уровне протокола — приложения остаются нетронутыми.

Трейсы на входном слое (Traefik) при этом сохраняются: Traefik пропагирует
`traceparent`, и сэмплер `parentbased_traceidratio` уважает решение родителя,
поэтому один запрос даёт и ingress-span, и span сервиса.

## Что отдаёт

| Компонент | Трейсы | Замечание |
| --- | --- | --- |
| LiveKit (Go) | да | first-class поддержка, плюс `application_runtime` (Go-рантайм) |
| lk-jwt-service (Go) | да | то же |
| Synapse (Python) | HTTP-уровень | eBPF видит протокол, но не бизнес-спаны внутри |
| coturn (C) | HTTP-уровень | то же |

## Развёртывание

```sh
kubectl apply -k apps/beyla
```

## Привилегии

Контейнер **не** `privileged`. Нужен `hostPID: true` (иначе Beyla не видит
процессы соседних контейнеров) и набор capabilities из официального
unprivileged-примера: `BPF`, `SYS_ADMIN`, `SYS_PTRACE`, `NET_RAW`,
`DAC_READ_SEARCH`, `PERFMON`, `CHECKPOINT_RESTORE`. Остальные capabilities
сброшены (`drop: [ALL]`), `readOnlyRootFilesystem: true`.

Это осознанное расширение поверхности безопасности кластера: eBPF требует
привилегий. Обоснование и альтернативы — в #542.

## Проверка

```sh
# поды
kubectl -n monitoring get pods -l app=beyla

# RED-метрики дошли до VictoriaMetrics
up{job="otel-collector"}                       # otel-collector уже скрейпится
http_server_request_duration_seconds_count     # метрики Beyla

# трейсы дошли до Tempo
# в Grafana: Explore → Tempo → service name: element-livekit / element-synapse
```

## Ограничения

- `hostPID: true` — единственное lint-исключение (`ignore-check.kube-linter.io/host-pid`).
- Beyla не заменяет OTel SDK в приложении: спаны на уровне HTTP-транзакции,
  без внутренних вызовов. Для глубины нужен SDK.
- `monitoring` (otelcol, alloy, сам Beyla) исключён через
  `default_exclude_instrument` — дублей телеметрии с коллектором нет.
- Объём eBPF-проб зависит от числа инструментируемых процессов. Сейчас
  ограничены одним namespace через `discovery.instrument`.
