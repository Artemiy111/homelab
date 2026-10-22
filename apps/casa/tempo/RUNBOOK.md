# Tempo: эксплуатация

## Проверка

Под и сервис:

```sh
kubectl get pod,svc -n monitoring -l app=tempo
```

Готовность:

```sh
kubectl -n monitoring exec deploy/grafana-deployment -- curl -s http://tempo:3200/ready
```

Трейсы доходят до Tempo (после нескольких запросов через Traefik):

```sh
kubectl -n monitoring exec deploy/grafana-deployment -- \
  curl -s 'http://tempo:3200/api/search?limit=5'
```

В Grafana — Explore, datasource `Tempo`.

## Расширение тома

Размер меняется в `tempo.pvc.yaml`, дальше Argo применяет изменение, а CSI-resizer
растит том Longhorn на месте. Под перезапускать не нужно, данные сохраняются.

```sh
kubectl -n monitoring get pvc tempo-data   # CAPACITY вырос, STATUS Bound
kubectl -n longhorn-system get volumes.longhorn.io | grep tempo
```

Уменьшить том нельзя: Longhorn не поддерживает shrink.
