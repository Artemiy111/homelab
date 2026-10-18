# VPA: эксплуатация

## Что считать признаком работы

```sh
kubectl -n vpa get deploy,issuer,certificate
kubectl -n vpa get pods
kubectl get crd verticalpodautoscalers.autoscaling.k8s.io verticalpodautoscalercheckpoints.autoscaling.k8s.io
kubectl get mutatingwebhookconfiguration vpa-webhook-config -o jsonpath='{.webhooks[0].clientConfig.caBundle}' | wc -c
```

Ожидаемо: три деплоймента `vpa-recommender`, `vpa-updater`,
`vpa-admission-controller` по одной реплике в `Ready`, `Issuer vpa-selfsigned`,
`Issuer vpa-ca` и `Certificate vpa-webhook-cert` в `Ready=True`, оба CRD
`Established`, а `caBundle` — не `0` (пустой `caBundle` означает, что
API-сервер не доверяет вебхуку и не ходит в него).

## Проверка рекомендаций

Рекомендации появляются от истории метрик, то есть не сразу: пять-десять минут
после установки.

```sh
kubectl get vpa -A
kubectl -n <ns> describe vpa <name> | sed -n '/Recommendation/,/Events/p'
```

Ожидаемо: блок `Recommendation` с `Target`, `Lower Bound` и `Upper Bound` по
`cpu` и `memory`. Пустой `Recommendation` — либо под молодой, либо недоступен
Metrics API (`kubectl top pods` тоже не работает).

## Проверка вебхука

Вебхук ломается молча: при `failurePolicy: Ignore` поды создаются как обычно,
просто без проставленных requests. Поэтому проверяем эффект, а не состояние
подов.

```sh
kubectl create namespace vpa-smoke

kubectl -n vpa-smoke create deployment smoke --image=registry.k8s.io/pause:3.10

kubectl -n vpa-smoke apply -f - <<'EOF'
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: smoke
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: smoke
  updatePolicy:
    updateMode: Initial
EOF

kubectl -n vpa-smoke describe vpa smoke | sed -n '/Recommendation/,/Events/p'

kubectl -n vpa-smoke delete pod -l app=smoke
kubectl -n vpa-smoke get pod -l app=smoke -o jsonpath='{.items[0].spec.containers[0].resources}{"\n"}'
```

Ожидаемо: `Recommendation` не пустая, а в пересозданном поде `requests` и
`limits` совпадают с ней. Если рекомендация есть, а под всё равно без requests —
API-сервер не доходит до вебхука: смотреть
`kubectl -n vpa logs deploy/vpa-admission-controller` (должны быть запросы на
`/admit`) и NetworkPolicy namespace'а `vpa`.

Убрать за собой:

```sh
kubectl delete namespace vpa-smoke
```

## Включить VPA для сервиса

Объект живёт в namespace сервиса, а не здесь. Первый шаг — `updateMode: Off`:
рекомендации считаются, поды не трогаются.

```sh
kubectl -n <ns> apply -f - <<'EOF'
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: <workload>
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: <workload>
  updatePolicy:
    updateMode: Off
EOF

kubectl -n <ns> describe vpa <workload>
```

Дальше режим меняется осознанно: `Initial` проставляет requests только при
создании пода, `Recreate` — перезапускает поды (простой), `InPlaceOrRecreate` —
меняет requests без перезапуска, если позволяет `resizePolicy` контейнера.

## Обновление версии

Версия чарта — `spec.sources[].targetRevision` в `Application`. CRD едут в
`templates/`, поэтому обновляются тем же синком; перед синком посмотреть diff:
`kubectl -n argocd get application vpa -o yaml` и синк в UI/CLI. Установка сразу
на 0.13.0, поэтому оговорка про `--take-ownership` из README чарта (апгрейд с
версий до 0.12, где CRD лежали в `crds/`) к этому стенду не относится.

```sh
kubectl -n argocd get application vpa -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{"\n"}'
```

Ожидаемо после синка: `Synced Healthy`.

## Удаление

`Application` создаёт кластерные CRD, и на удалении Application Argo удаляет всё,
что под ним: вместе с CRD уйдут **все** `VerticalPodAutoscaler` всех сервисов.
Аннотация `helm.sh/resource-policy: keep` на CRD от этого не защищает — её
понимает Helm, а не Argo.

Безопасный порядок:

```sh
kubectl get vpa -A
kubectl -n <ns> delete vpa <name>
kubectl delete -f clusters/casa/argocd/platform/vpa.yaml
```

Если нужно снять именно контроллер, оставив объекты VPA (они станут «мёртвыми»
до возврата контроллера):

```sh
kubectl -n argocd patch application vpa --type=merge -p '{"metadata":{"finalizers":null}}'
kubectl -n argocd delete application vpa
```

## Диагностика

| Симптом | Причина и что смотреть |
|---|---|
| `recommender` в `OOMKilled` | мало лимита памяти; история при рестарте теряется, рекомендации набираются заново |
| у VPA пустая `Recommendation` | нет истории метрик или недоступен Metrics API (`kubectl top pods`) |
| поды не перезапускаются в `Recreate` | PDB сервиса, `--in-place-skip-disruption-budget`, или requests уже равны рекомендации |
| requests не проставляются новым подам | вебхук недоступен: `kubectl -n vpa logs deploy/vpa-admission-controller`, NetworkPolicy, `caBundle` в `MutatingWebhookConfiguration` |
| `Certificate vpa-webhook-cert` не `Ready` | `Issuer`/`Certificate`: `kubectl -n vpa describe certificate vpa-webhook-cert` |
| VPA и HPA спорят | на одном workload'е включены оба; HPA считать утилизацию от requests, которые двигает VPA, нельзя |
