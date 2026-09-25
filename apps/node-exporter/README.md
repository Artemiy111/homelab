# node-exporter

Стандартный Prometheus-экспортер метрик хоста: отдаёт `node_*` (CPU, память, ФС,
сеть, load, pressure и т.д.) в формате exposition. Работает как DaemonSet — один
под на ноду, читает host-каталоги `/proc`, `/sys`, `/` через маунты
`/host/...`; hostNetwork не используется, порт наружу не публикуется.

Дублирует часть того, что уже собирает netdata, но `node_*` — это то, на что
написаны готовые Grafana-дашборды и Prometheus-правила.

## Состав

Манифесты в `apps/node-exporter/k8s/`:

- `daemonset.yaml` — DaemonSet, образ зафиксирован по digest;
- `service.yaml` — ClusterIP, порт 9100 для vmagent.

Скрейпит vmagent (job `node-exporter` в
`apps/victoria-metrics/config/vmagent/scrape.yml`).

## Развёртывание

```sh
kubectl apply --server-side --field-manager=homelab -f apps/node-exporter/k8s/
```

## Проверка

```sh
kubectl exec deploy/victoriametrics -- wget -qO- \
  'http://127.0.0.1:8428/api/v1/query?query=up{job="node-exporter"}'
kubectl exec deploy/victoriametrics -- wget -qO- \
  'http://127.0.0.1:8428/api/v1/label/__name__/values?match[]={job="node-exporter"}'
```
