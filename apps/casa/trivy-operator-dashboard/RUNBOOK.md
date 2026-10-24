# Trivy Operator Dashboard: эксплуатация

## Проверка на стенде

Приложение и под:

```sh
kubectl -n argocd get application trivy-operator-dashboard
kubectl -n trivy-operator-dashboard get pods
```

Ожидается `Synced`/`Healthy` и под `Running`/`Ready`. В `Events` не должно быть
`Namespace is not permitted in project` — это значит, что namespace юнита не
вписан в `clusterResourceWhitelist` проекта `homelab-cluster-readers`.

Приложение отвечает:

```sh
kubectl -n trivy-operator-dashboard port-forward svc/trivy-operator-dashboard 8900:8900
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8900/healthz/ready
```

Ожидается `200`. Пустой ответ или `503` — приложение поднялось, но ещё не готово
читать API: смотреть логи пода.

## Данные в UI

Число находок в UI сверяется с кластером:

```sh
kubectl get vulnerabilityreports -A -o json |
  jq '[.items[].report.summary.criticalCount] | add'
```

Ожидается то же число на странице уязвимостей. Расхождение — не поломка UI, а
разные моменты сканирования: отчёты обновляются в фоне.

Права ServiceAccount'а проверяются отдельно:

```sh
kubectl auth can-i list vulnerabilityreports.aquasecurity.github.io \
  --all-namespaces \
  --as=system:serviceaccount:trivy-operator-dashboard:trivy-operator-dashboard
```

Ожидается `yes`. `no` — правку RBAC в чарте перекрыли values или проект.

## Вход

Маршрут открывается в браузере и уводит на общий OIDC-логин. Признак того, что
`oauth2-proxy` не пускает: `302` на `/oauth2/start` по кругу или `401` вместо
страницы.

```sh
kubectl -n trivy-operator-dashboard get httproute trivy-operator-dashboard
kubectl -n traefik get middleware oauth2-proxy 2>/dev/null || \
  kubectl -n monitoring get middleware oauth2-proxy
```

`Accepted=True` и смонтированная цепочка middleware означают, что проблема не в
маршруте, а в сессии: чистится удалением cookie домена.

## Обновление версии

Новая версия приходит тегом чарта и дайджестом образа, их надо менять вместе:

```sh
curl -s "https://ghcr.io/token?scope=repository:raoulx24/trivy-operator-dashboard:pull&service=ghcr.io" |
  jq -r .token
curl -sI -H "Authorization: Bearer <token>" \
  -H 'Accept: application/vnd.oci.image.index.v1+json' \
  https://ghcr.io/v2/raoulx24/trivy-operator-dashboard/manifests/<тег> |
  grep -i docker-content-digest
```

Дайджест вписывается в `values.yaml` рядом с тегом, тег чарта — в
`targetRevision` Application. После merge дайджест в коде перестаёт совпадать с
образом, только если в git попал тег без дайджеста — это ловится на ревью.

Откат: вернуть предыдущую пару «тег + дайджест» и засинкать Application.

## Диагностика

| Симптом | Что смотреть |
|---|---|
| Под в `CrashLoopBackOff` | `kubectl -n trivy-operator-dashboard logs deploy/trivy-operator-dashboard --previous` |
| Страница открылась, списки пустые | `kubectl auth can-i` выше; затем `kubectl -n trivy-system get pods` и `kubectl get vulnerabilityreports -A \| wc -l` |
| `502` на маршруте | `kubectl -n trivy-operator-dashboard get endpoints trivy-operator-dashboard` — пустой список значит, что под не прошёл readiness |
| Приложение перезапускается по liveness | `kubectl -n trivy-operator-dashboard describe pod` — смотреть, не упирается ли оно в лимит памяти |

## Удаление

```sh
kubectl -n argocd delete application trivy-operator-dashboard
kubectl delete ns trivy-operator-dashboard
kubectl delete clusterrole,clusterrolebinding trivy-operator-dashboard
```

Namespace помечен `Prune=false`, поэтому Argo его не удаляет — это делается
руками. ClusterRole и ClusterRoleBinding принадлежат чарту и удаляются вместе с
Application; отдельная команда нужна, если Application удалили без каскада.
