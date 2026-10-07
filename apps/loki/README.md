# Loki

Хранилище логов. Принимает push по Loki HTTP API от Grafana Alloy
(`apps/alloy/`) и отдаёт логи Grafana как datasource. Развёрнут в namespace
`monitoring`; наружу не публикуется — доступ только через Grafana.

Модель — монолит в одном поде (`grafana/loki`), хранение на локальном диске
(файловая система), индексируются только лейблы, содержимое строк сжато.

```
Alloy (DaemonSet) ──push──> loki:3100 <── Grafana (Explore)
```

## Состав

- `config/loki.yaml` — конфиг: `auth_enabled: false`, схема `tsdb`/`v13`,
  filesystem-хранилище, retention 168 ч (7 суток);
- `kustomization.yaml` — собирает `config/loki.yaml` в ConfigMap `loki-config`
  (kustomize добавляет хэш содержимого к имени);
- `k8s/loki.deployment.yaml` — один под, образ зафиксирован по digest,
  runAsUser/fsGroup `10001`;
- `k8s/loki.pvc.yaml` — PVC `loki-data` (Longhorn, `longhorn-retain`, 10 Ги);
- `k8s/loki.service.yaml` — ClusterIP, порт 3100.

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
