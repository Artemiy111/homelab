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

## Привилегии

Контейнер **не** `privileged`. Нужен `hostPID: true` (иначе Beyla не видит
процессы соседних контейнеров) и набор capabilities из официального
unprivileged-примера: `BPF`, `SYS_ADMIN`, `SYS_PTRACE`, `NET_RAW`,
`DAC_READ_SEARCH`, `PERFMON`, `CHECKPOINT_RESTORE`. Остальные capabilities
сброшены (`drop: [ALL]`), `readOnlyRootFilesystem: true`.

Это осознанное расширение поверхности безопасности кластера: eBPF требует
привилегий. Обоснование и альтернативы — в #542.

## Выключена

Инструментация не работает: DaemonSet планируется только на узлы с лейблом
`homelab.io/beyla=enabled`, а таких узлов нет. Application при этом
синхронизирован, и в `kubectl get ds` видно `DESIRED 0` — выключенное состояние
не выглядит как расхождение с git.

Причина — стоимость eBPF-агента: на одном узле он конкурирует с рабочими
нагрузками, а трейсы и логи Element без него остаются работоспособными
(трейсы приложений идут через `otel-collector`). Включение и выключение —
`RUNBOOK.md`.

## Ограничения

- `hostPID: true` — единственное lint-исключение (`ignore-check.kube-linter.io/host-pid`).
- Beyla не заменяет OTel SDK в приложении: спаны на уровне HTTP-транзакции,
  без внутренних вызовов. Для глубины нужен SDK.
- `monitoring` (otelcol, alloy, сам Beyla) исключён через
  `default_exclude_instrument` — дублей телеметрии с коллектором нет.
- Объём eBPF-проб зависит от числа инструментируемых процессов. Сейчас
  ограничены одним namespace через `discovery.instrument`.

Проверка — в `RUNBOOK.md`.
