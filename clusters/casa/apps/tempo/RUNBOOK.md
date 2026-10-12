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
