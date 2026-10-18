# Loki: эксплуатация

## Проверка

Под и готовность:

```sh
kubectl -n monitoring get pods -l app=loki
kubectl -n monitoring exec deploy/grafana-deployment -- curl -s http://loki:3100/ready
```

Есть ли потоки (например, `namespace="monitoring"`):

```sh
kubectl -n monitoring exec deploy/grafana-deployment -- \
  curl -s 'http://loki:3100/loki/api/v1/label/namespace/values'
```

В Grafana — Explore, datasource `Loki`, запрос `{namespace="monitoring"}`.
