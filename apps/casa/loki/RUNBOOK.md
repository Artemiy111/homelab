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

## Расширение тома

Размер меняется в `loki.pvc.yaml`, дальше Argo применяет изменение, а CSI-resizer
растит том Longhorn на месте. Под перезапускать не нужно, данные сохраняются.

```sh
kubectl -n monitoring get pvc loki-data   # CAPACITY вырос, STATUS Bound
kubectl -n longhorn-system get volumes.longhorn.io | grep loki
```

Уменьшить том нельзя: Longhorn не поддерживает shrink.
