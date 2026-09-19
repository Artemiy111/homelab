# Argo CD (пробный стенд)

Argo CD поднимается на кластере как **проверка второго GitOps-инструмента**:
целевое решение — Flux (см. `docs/research/k8s/argo-cd-vs-flux-cd.md`), но
разницу между «Argo рендерит манифесты сам» и «Flux управляет Helm-релизом»
полезно пощупать руками, а не вычитать.

| | |
|---|---|
| Чарт | `argo/argo-cd` 10.9.1 (community-maintained) |
| Argo CD | v3.5.3 |
| Namespace | `argocd` |
| URL | https://argocd.example.com |
| Параметры | `k8s/argocd/values.yaml` — только отклонения от дефолтов чарта |
| Маршрут | `k8s/traefik/argocd.ingressroute.yaml` |

Все команды ниже выполняются **на сервере** (там есть `helm` и kubeconfig),
из корня репозитория.

## Установка

```sh
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Сначала посмотреть, что получится, не трогая кластер:
helm template argocd argo/argo-cd --version 10.9.1 -f k8s/argocd/values.yaml | less

helm install argocd argo/argo-cd \
  --version 10.9.1 \
  --namespace argocd --create-namespace \
  -f k8s/argocd/values.yaml \
  --wait

kubectl apply -f k8s/traefik/argocd.ingressroute.yaml
```

## Проверка

```sh
kubectl -n argocd get pods
```

Ожидаемо пять подов: `argocd-application-controller-0`,
`argocd-applicationset-controller`, `argocd-redis`, `argocd-repo-server`,
`argocd-server`. Отдельный под `dex` не появится — он отключён в values.

```sh
curl --resolve argocd.example.com:443:192.0.2.10 \
  -o /dev/null -sS -w '%{http_code}\n' https://argocd.example.com
```

Ожидаемо `200` (страница логина). `5xx` и transport error — ошибка.

## Вход

Пароль admin генерируется один раз при установке:

```sh
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Дальше https://argocd.example.com, логин `admin`.

CLI — два способа, потому что gRPC через прокси капризен:

```sh
# 1) через ингресс, поверх HTTP/1.1 (grpc-web)
argocd login argocd.example.com --grpc-web

# 2) через port-forward, вообще минуя Traefik
kubectl -n argocd port-forward svc/argocd-server 8080:80 &
argocd login localhost:8080 --plaintext
```

`--plaintext` нужен именно потому, что стоит `server.insecure: true` — Argo
отдаёт чистый HTTP. Если `argocd` CLI ещё не установлен:

```sh
curl -sSL -o /tmp/argocd https://github.com/argoproj/argo-cd/releases/download/v3.5.3/argocd-linux-amd64
sudo install -m 0755 /tmp/argocd /usr/local/bin/argocd
```

Сразу после первого входа:

```sh
argocd account update-password
```

## Что проверять в рамках эксперимента

Задача стенда — сравнить механики, поэтому смотреть стоит именно на них:

1. **Self-heal (главное отличие от Terraform).** Создать приложение, потом
   вручную увести кластер в сторону — Argo вернёт сам:
   ```sh
   argocd app create guestbook \
     --repo https://github.com/argoproj/argocd-example-apps.git \
     --path guestbook --dest-server https://kubernetes.default.svc \
     --dest-namespace argocd-trial \
     --sync-policy automated --self-heal --auto-prune
   kubectl -n argocd-trial scale deploy guestbook-ui --replicas=5
   ```
2. **Отсутствие Helm-релиза.** `helm list -n argocd-trial` пуст: Argo сделал
   `helm template` и применил результат сам. Сравнить с тем, как повёл бы себя
   Flux `HelmRelease`.
3. **Порядок в Helm-чартах.** У Argo его задают sync-waves
   (`argocd.argoproj.io/sync-wave`), а не `dependsOn`, как во Flux.
4. **`lookup` не работает.** Чарты, читающие существующие объекты кластера при
   шаблонизации (генерация паролей), отрендерятся с пустыми значениями.
5. **ApplicationSet** — генератор приложений из git-директорий и списка
   кластеров вместо ручного создания каждого Application.

## Обновление Application: спека живёт в кластере

Application'ы применяются руками (`kubectl apply -f k8s/argocd/<name>.yaml`), app-of-apps
здесь нет. Поэтому Argo читает желаемое состояние **из объекта в кластере**, а манифест в git
нужен только чтобы не потерять это состояние: пока файл не применён, правка values в git
ничего не меняет (приложение остаётся `Synced` на старой спеке).

```sh
kubectl apply -f k8s/argocd/local-path-provisioner.yaml   # обновить спеку
argocd app sync local-path-provisioner                    # или ручной sync, см. ниже
```

Ещё две вещи, которые полезно знать до того, как что-то менять:

- **Упавший sync не повторяется сам.** После ошибки контроллер логирует
  `failed previous sync attempt ... will not retry` и ждёт новый revision или ручной sync,
  даже при включённом `automated`. Форсировать из кластера (без CLI):
  ```sh
  kubectl -n argocd patch application local-path-provisioner --type merge \
    -p '{"operation":{"sync":{"prune":true}}}'
  ```
  (`operation` — поле верхнего уровня Application, не в `spec`.)
- **Immutable-поля Kubernetes не дают Argo починить дрейф** — типовая история: StorageClass
  (`reclaimPolicy`, `volumeBindingMode`, `provisioner`, `parameters`) или Service (`clusterIP`).
  Argo будет вечно `OutOfSync` с `field is immutable`; лечится удалением объекта, после чего
  Argo создаёт его заново.

## kube-state-metrics (боевой компонент под Argo)

`kube-state-metrics.yaml` — Application, который ставит официальный чарт
`prometheus-community/kube-state-metrics` в namespace `default`. Он отдаёт
метрики состояния объектов кластера (`kube_*`), которых нет у node-exporter.
Это уже не пробный стенд, а рабочий компонент, поэтому держать его нужно
**только** под Argo — не дублировать манифестами для будущего Flux.

```sh
kubectl apply -f k8s/argocd/kube-state-metrics.yaml
argocd app get kube-state-metrics
argocd app diff kube-state-metrics
```

`syncPolicy` автоматический (prune + selfHeal): Argo сам приводит кластер к
состоянию чарта. Проверка self-heal — увести ресурс в сторону и дождаться
возврата (сравнимо с ручным `helm upgrade`):

```sh
kubectl -n default scale deploy kube-state-metrics --replicas=3
argocd app get kube-state-metrics
```

Метрики скрейпит vmagent (job `kube-state-metrics` в
`apps/victoria-metrics/config/vmagent/scrape.yml`) — после синка нужно
перезапустить vmagent.

## Адопция существующего Helm-релиза (на примере headlamp)

`headlamp.yaml` переводит уже работающий Helm-релиз под Argo **без
пересоздания** ресурсов. Порядок применим и к боевому Traefik.

```sh
kubectl apply -f k8s/argocd/headlamp.yaml

argocd app diff headlamp        # желаемое (чарт) vs живое: расхождений быть не должно
argocd app sync headlamp        # server-side apply берёт ownership, Pod не пересоздаётся

kubectl -n headlamp get pods    # AGE не должен сброситься
```

Так как релиз ставился Helm 4 (server-side apply), адопция идёт
`ServerSideApply=true` — иначе client-side apply полез бы чинить
`last-applied-configuration`, которого Helm не оставляет.

Дальше нужно «забыть» Helm-релиз, чтобы `helm upgrade` не конкурировал с Argo.
Опции «удалить релиз, но оставить ресурсы» у Helm нет: `--keep-resources` не
существует ни в 3, ни в 4, а `--cascade orphan` — это лишь propagation policy
при удалении самих объектов. Рабочий способ — удалить release-секреты; ресурсы
при этом не трогаются, а релиз пропадает из `helm list`:

```sh
kubectl -n headlamp delete secret -l owner=helm,name=headlamp
```

Проверка: `helm list -n headlamp` пуст, ресурсы и Pod на месте.

Границы владения: чарт по умолчанию создаёт `ClusterRoleBinding headlamp-admin`
на SA пода `headlamp` — то есть выдаёт cluster-admin самому поду. Здесь это
выключено (`clusterRoleBinding.create: false`): под остаётся бесправным и
бежит под SA `headlamp`, а cluster-admin получает отдельный логин-аккаунт
`headlamp-admin`. SA, `ClusterRoleBinding` на него и token-Secret описаны через
`extraManifests` в том же Application (раньше — вручную в
`k8s/headlamp/headlamp-rbac.yaml`). `ignoreDifferences` по `/data` и аннотации
`kubernetes.io/service-account.uid` нужен, потому что их дописывает контроллер
service-account. Маршрут (`k8s/headlamp/headlamp.ingressroute.yaml`) —
по-прежнему вне Application.

### Traefik

`traefik.yaml` — тот же приём для боевого ingress (единственный вход на
`192.0.2.10`, поэтому проверять `argocd app diff` особенно внимательно).
Отличия от headlamp:

- `skipCrds: true` — CRD `*.traefik.io` кластерные; под управлением Argo они
  при удалении приложения снесли бы все `IngressRoute`/`Middleware` кластера.
- values продублированы из `k8s/traefik/values.yaml` инлайном. При правке
  values менять оба места, иначе кластер уедет от файла. Альтернатива —
  завести Argo repo credentials и ссылаться на `$values/...`.
- Чарт сам создаёт `ClusterRole`/`ClusterRoleBinding`/`IngressClass` — они под
  управлением Argo (в отличие от RBAC headlamp, который вне чарта).

### sealed-secrets

`sealed-secrets.yaml` — адопция боевого контроллера в `kube-system`. Отличия:

- `skipCrds: true` — CRD `sealedsecrets.bitnami.com` кластерный, обновляется
  вручную (`helm show crds ... | kubectl apply -f -`).
- values — только `fullnameOverride`; без него ресурсы назывались бы
  `sealed-secrets`, а не `sealed-secrets-controller`.
- приватный ключ `sealed-secrets-key*` чартом не управляется, Argo его не
  трогает.
- после адопции забыть Helm-релиз:
  `kubectl -n kube-system delete secret -l owner=helm,name=sealed-secrets`.

## Отклонения от дефолтов чарта

| Параметр | Дефолт | Здесь | Зачем |
|---|---|---|---|
| `global.domain` | `argocd.example.com` | реальный домен | попадает в генерируемые URL |
| `configs.params."server.insecure"` | `false` | `true` | TLS терминирует Traefik |
| `configs.cm."timeout.reconciliation"` | `120s` | `60s` | реактивнее на одном репо |
| `dex.enabled` | `true` | `false` | SSO будет внешний (authentik) |
| `notifications.enabled` | `true` | `false` | контроллер уведомлений пока не нужен |
| `*.resources` | `{}` | заданы | однозный кластер: без limits контроллер может вытеснить приложения |

## Удаление

```sh
# Сначала приложения и их ресурсы, иначе финалайзеры подвесят удаление namespace
argocd app list -A
argocd app delete guestbook --cascade

helm uninstall argocd -n argocd
kubectl delete -f k8s/traefik/argocd.ingressroute.yaml
kubectl delete ns argocd

# CRD чарт намеренно не удаляет (crds.keep: true) — снимаем руками
kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io
```

## ⚠️ Argo CD и Flux одновременно

Два GitOps-контроллера, ведущие один и тот же объект к разным желаемым
состояниям, — это гарантированный «пинг-понг» и непонятные случайные откаты.

Пока стенд живёт вместе с будущим Flux:

- держать Argo на **отдельном** наборе ресурсов: тестовые приложения, а не
  боевые манифесты кластера из `k8s/`;
- не указывать обоим контроллерам один и тот же git-путь;
- помнить, что Argo ставится Helm'ом, а Flux будет управлять собой сам —
  их собственные манифесты в кластере тоже не должны пересекаться.

## Источники

- [argo-cd Helm chart](https://artifacthub.io/packages/helm/argo/argo-cd)
- [Argo CD Operator Manual](https://argo-cd.readthedocs.io/en/stable/operator-manual/)
- [docs/research/k8s/argo-cd-vs-flux-cd.md](../../docs/research/k8s/argo-cd-vs-flux-cd.md)
- [docs/research/k8s/k0s-kubernetes-distribution.md](../../docs/research/k8s/k0s-kubernetes-distribution.md)
