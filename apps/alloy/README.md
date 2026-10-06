# Grafana Alloy

Агент сбора логов. DaemonSet на каждой ноде тянет логи подов **этой** ноды через
Kubernetes API и пушит их в Loki. Выбран вместо Promtail (тот объявлен EOL) и
вместо Filebeat/ELK (стек выведен из эксплуатации, см. `apps/elk/README.md`).

```
API сервера ──(pods/log)──> alloy ──push──> loki:3100
```

## Почему через API, а не через файлы

`loki.source.kubernetes` читает логи по API Kubernetes (`pods/log`), а не файлы
`/var/log/pods` на хосте. Это убирает root, privileged-режим и hostPath, а
метаданные пода приходят штатно. `discovery.kubernetes` при этом фильтрует поды
по `spec.nodeName`, поэтому каждый под Alloy обрабатывает только свою ноду — без
этого DaemonSet дублировал бы логи всего кластера.

## Состав

- `config/config.alloy` — `discovery.kubernetes` (роль pod, фильтр по ноде) →
  `discovery.relabel` (лейблы `namespace`/`pod`/`container`/`job`) →
  `loki.source.kubernetes` → `loki.process` → `loki.write` в
  `loki.monitoring.svc:3100`; логи узла — `loki.source.journal` (systemd).
  В `loki.process` сначала редактируются секреты (значения после ключей
  password/token/... , Bearer-токены, JWT), затем строки разбираются:
  `level`/`trace_id`/`span_id` и поля Gatus/klog уходят в structured metadata;
- `kustomization.yaml` — собирает конфиг в ConfigMap `alloy-config`;
- `k8s/alloy.daemonset.yaml` — DaemonSet (`grafana/alloy`, образ по digest),
  env `NODE_NAME` из Downward API, non-root; для journald — hostPath
  `/var/log/journal`, `/run/log/journal`, `/etc/machine-id` и
  `supplementalGroups: [190]` (группа systemd-journal);
- `k8s/alloy-rbac.yaml` — ServiceAccount + ClusterRole на `pods`/`namespaces`/
  `nodes` (list/watch) и `pods/log` (get);
- `k8s/alloy.service.yaml` — Service для скрейпа `/metrics` (:12345) vmagent'ом.

Ошибок чтения логов и записи в Loki быть не должно; в Loki появляются потоки с
лейблами `namespace`, `pod`, `container`, `job`.
