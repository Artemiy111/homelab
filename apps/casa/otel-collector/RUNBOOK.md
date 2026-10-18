# OpenTelemetry Collector: эксплуатация

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
