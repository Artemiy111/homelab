# caretta

Namespace `caretta`: DaemonSet агента, VictoriaMetrics и Grafana.

Все команды — с `KUBECONFIG=~/.kube/configs/yc.yaml`.

## Проверить, что приехало

```sh
flux -n flux-system get kustomization caretta
flux -n flux-system get helmrelease caretta
kubectl -n caretta get pods
```

Ожидается: `Kustomization` и `HelmRelease` в состоянии Ready; поды
`caretta-*` — по одному на каждом узле, все Running; рядом Running
`caretta-grafana-*` и `caretta-victoria-metrics-single-0`.

## Открыть карту

```sh
kubectl -n caretta port-forward svc/caretta-grafana 3000:80
```

Открыть `http://localhost:3000`, дашборд «Caretta». Вход не нужен: в чарте
включён анонимный доступ. Для правки дашборда — пользователь `admin` и пароль из
значений субчарта Grafana в чарте.

## Проверить, что метрики есть

Напрямую у агента:

```sh
kubectl -n caretta port-forward pod/<caretta-pod> 7117:7117
curl -sS localhost:7117/metrics | grep '^caretta_links_observed' | head
```

Пусто — значит за время жизни пода через узел не прошло TCP-соединений.
Сгенерировать трафик:

```sh
kubectl -n test-nginx run traffic --rm -it --restart=Never --image=curlimages/curl -- \
  curl -sS -o /dev/null http://test-nginx.test-nginx.svc.cluster.local
```

Через VictoriaMetrics:

```sh
kubectl -n caretta port-forward svc/caretta-vm 8428:8428
curl -sS 'localhost:8428/api/v1/query?query=count(caretta_links_observed)'
```

Ожидается непустой `data.result` со счётчиком связей.

## Обновить версию

Версия чарта — `spec.chart.spec.version`, версия образа — `spec.values.image.tag`
в `releases/helmrelease.yaml`. Двигаются независимо: у проекта чарт и образ
обновляются не синхронно. До PR проверить, что версия чарта существует:

```sh
helm repo update groundcover
helm search repo groundcover/caretta --versions
```

Flux применит изменение после того, как Forgejo отдаст коммит в GitHub-зеркало.

## Диагностика

| Симптом | Что смотреть |
| --- | --- |
| под агента в CrashLoopBackOff, `lastState.terminated.reason: OOMKilled` | лимита памяти не хватает на разбор BTF текущего ядра |
| в логах `error loading BPF objects` или `Verifier Error` | ядро не приняло eBPF-программу: сверить версию ядра и наличие `/sys/kernel/btf/vmlinux` на узле |
| `Warning: couldn't retrieve owner ... - Node` в логах | норма: у узлов нет владельца, связи с ними остаются в карте как есть |
| в Grafana «No data» | скрейп: `kubectl -n caretta logs sts/caretta-victoria-metrics-single`; датасорс `Prometheus` должен указывать на `http://caretta-vm:8428` |
| метрика есть, карта пустая | увеличить окно на панели: графики считают `increase` за интервал |

## Удалить

Убрать `platform/caretta.yaml` из `clusters/yc/kustomization.yaml`; Flux удалит
`Kustomization` и вместе с ним `HelmRelease` (prune). Namespace Helm при удалении
релиза не удаляет, поэтому:

```sh
kubectl delete ns caretta
```

PVC у юнита нет, так что удаляется всё без остатка.
