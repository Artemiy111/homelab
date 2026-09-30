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

## Состав

- `config/config.yaml` — pipeline: receiver `otlp` (gRPC 4317, HTTP 4318) →
  exporter `prometheus` (8889) с `resource_to_telemetry_conversion`, чтобы
  resource-атрибуты (напр. `service_name`) становились лейблами, и exporter
  `otlp/tempo` для трейсов; processors `memory_limiter` и `batch`; extension
  `health_check` (13133);
- `kustomization.yaml` — собирает `config/config.yaml` в ConfigMap
  `otel-collector` (kustomize добавляет хэш содержимого к имени);
- `k8s/deployment.yaml` — один под, образ зафиксирован по digest;
- `k8s/service.yaml` — ClusterIP, порты 4317/4318 (приём) и 8889 (скрейп).

## Развёртывание

```sh
kubectl apply -k apps/otel-collector/
```

## Подключение приложения

RustFS шлёт OTLP на этот коллектор (`RUSTFS_OBS_ENDPOINT` в его Deployment).
Open WebUI шлёт метрики по OTLP/gRPC (`ENABLE_OTEL*` в его Deployment).
Чтобы добавить ещё сервис — нужно указать ему **FQDN** коллектора
`http://otel-collector.monitoring.svc.cluster.local:4318` (HTTP) или `:4317`
(gRPC): короткое имя `otel-collector` резолвится только внутри namespace
`monitoring`. Отдельный scrape-job не нужен — метрики придут в job
`otel-collector`. Дополнительно namespace приложения надо внести в
`platform/monitoring/networkpolicy.yaml` (default-deny ingress) на порты
4317/4318. Трейсы принимаются на тот же эндпоинт и уходят в Tempo
(`apps/tempo/`).

## Проверка

Метрики:

```sh
kubectl exec deploy/victoriametrics -- wget -qO- \
  'http://127.0.0.1:8428/api/v1/label/__name__/values?match[]={job="otel-collector"}'
```

`up{job="otel-collector"}=1` и наличие `rustfs_*` метрик с лейблом
`service_name="rustfs"`.

Принятые трейсы (растёт при запросах через Traefik) видны в Tempo:

```sh
kubectl -n monitoring exec deploy/grafana-deployment -- \
  curl -s 'http://tempo:3200/api/search?limit=5'
```
