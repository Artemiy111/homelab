# OpenTelemetry Collector

Принимает телеметрию по OTLP (push) и переотдаёт метрики в Prometheus-формате,
чтобы vmagent мог их скрейпить обычным pull'ом. Нужен для приложений, которые
не отдают нативный `/metrics`, а только push'ат OTLP — сейчас это RustFS.

```
RustFS ──OTLP──> otel-collector:4318 ──Prometheus──> :8889 <──vmagent
```

## Состав

Манифесты в `apps/otel-collector/k8s/`:

- `configmap.yaml` — pipeline: receiver `otlp` (gRPC 4317, HTTP 4318) →
  exporter `prometheus` (8889) с `resource_to_telemetry_conversion`, чтобы
  resource-атрибуты (напр. `service_name`) становились лейблами; extension
  `health_check` (13133);
- `deployment.yaml` — один под, образ зафиксирован по digest;
- `service.yaml` — ClusterIP, порты 4317/4318 (приём) и 8889 (скрейп).

## Развёртывание

```sh
kubectl apply -f apps/otel-collector/k8s/
```

## Подключение приложения

RustFS шлёт OTLP на этот коллектор (`RUSTFS_OBS_ENDPOINT` в его Deployment).
Чтобы добавить ещё сервис — достаточно указать ему OTLP-эндпоинт
`http://otel-collector:4318` (или gRPC `:4317`); отдельный scrape-job не нужен,
метрики придут в тот же job `otel-collector`.

## Проверка

```sh
kubectl exec deploy/victoriametrics -- wget -qO- \
  'http://127.0.0.1:8428/api/v1/label/__name__/values?match[]={job="otel-collector"}'
```

`up{job="otel-collector"}=1` и наличие `rustfs_*` метрик с лейблом
`service_name="rustfs"`.
