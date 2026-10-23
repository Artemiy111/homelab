# metrics-server

Источник ресурсных метрик для `kubectl top` и HPA: поднимает API `metrics.k8s.io` поверх `/metrics/resource` каждого kubelet'а.

## Почему чартом через Flux, а не addon'ом kubespray

kubespray умеет ставить metrics-server сам (`roles/kubernetes-apps/metrics_server`), но кластер уже управляется GitOps: всё, что живёт внутри, видно в репозитории, обновляется сменой версии и откатывается из git. Addon пришлось бы дёргать плейбуком с macOS, и он начал бы владеть теми же объектами, что и Flux. Два хозяина у одного Deployment дают дрейф, который обнаруживается только пересборкой кластера.

Поэтому здесь `HelmRelease` официального чарта `kubernetes-sigs/metrics-server` — как `envoy-gateway`, только без слоя конфигурации: собственных CR у компонента нет.

## Почему `--kubelet-insecure-tls`

metrics-server ходит к kubelet'ам по `https://<InternalIP>:10250`, а kubelet отдаёт **self-signed** сертификат с SAN только `DNS:<имя узла>`:

```
issuer=CN = yc-d1-ca@1792757095
X509v3 Subject Alternative Name:
    DNS:yc-d1
```

Проверить такой сертификат нечем: издатель неизвестен, IP в SAN нет. Это ровно то, ради чего в kubespray есть `metrics_server_kubelet_insecure_tls: true`.

Правильное лечение — не флаг, а ротация kubelet serving-сертификатов: тогда их подписывает CA кластера, SAN включает адреса узла, и проверка становится возможной. Это отдельная задача про kubelet, а не про metrics-server.

## Что здесь лежит

| Файл | Зачем |
| --- | --- |
| `releases/helmrepository.yaml` | `HelmRepository` на `https://kubernetes-sigs.github.io/metrics-server/` |
| `releases/helmrelease.yaml` | `HelmRelease` чарта в `kube-system`, версия закреплена в `chart.spec.version` |

## Проверка

```sh
flux -n flux-system get helmrelease metrics-server
kubectl get apiservice v1beta1.metrics.k8s.io          # Available=True
kubectl top nodes
kubectl top pods -A
```

## Чего здесь нет

- **Метрик кластера сверх ресурсных.** `metrics.k8s.io` отдаёт только CPU и память подов и узлов, без истории: `kubectl top` — мгновенный срез, а не график. История, алерты и custom-метрики — задача отдельного стека (Prometheus или VictoriaMetrics), metrics-server его не заменяет и не заменяется им.
- **HA.** Одна реплика, как в дефолте чарта и в addon'е kubespray: метрики — не критичный путь, а лишняя реплика на узле в 4 ГБ не окупается. При этом `kubectl top` переживает рестарт пода.
