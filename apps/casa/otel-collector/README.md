# OpenTelemetry Collector

Принимает телеметрию по OTLP (push): метрики переотдаёт в Prometheus-формате,
чтобы vmagent мог их скрейпить обычным pull'ом, а трейсы — в Tempo по OTLP.
Нужен для приложений, которые не отдают нативный `/metrics`, а только push'ат
OTLP (сейчас это RustFS), и как единая точка приёма трейсов (Traefik).

```
RustFS ──OTLP──> otel-collector:4318 ──Prometheus──> :8889 <──vmagent
Open WebUI ──OTLP/gRPC──> otel-collector:4317
Traefik ──OTLP──> otel-collector:4318 ──OTLP──> tempo:4317
```

## Как устроен

Pipeline: receiver `otlp` (gRPC 4317, HTTP 4318) → exporter `prometheus` (8889) с
`resource_to_telemetry_conversion`, чтобы resource-атрибуты (напр. `service_name`)
становились лейблами, и exporter `otlp/tempo` для трейсов; processors
`memory_limiter` и `batch`; extension `health_check` (13133).

## Подключение приложения

RustFS шлёт OTLP на этот коллектор (`RUSTFS_OBS_ENDPOINT` в его Deployment).
Open WebUI шлёт метрики по OTLP/gRPC (`ENABLE_OTEL*` в его Deployment).
Чтобы добавить ещё сервис — нужно указать ему **FQDN** коллектора
`http://otel-collector.monitoring.svc.cluster.local:4318` (HTTP) или `:4317`
(gRPC): короткое имя `otel-collector` резолвится только внутри namespace
`monitoring`. Отдельный scrape-job не нужен — метрики придут в job
`otel-collector`. Дополнительно namespace приложения надо внести в
`platform/casa/monitoring/manifests/networkpolicy.yaml` (default-deny ingress) на порты
4317/4318. Трейсы принимаются на тот же эндпоинт и уходят в Tempo
(`apps/casa/tempo/`).

Проверка — в `RUNBOOK.md`.
