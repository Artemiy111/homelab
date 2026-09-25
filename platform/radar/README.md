# Radar (Kubernetes UI)

| | |
|---|---|
| Чарт | `radar` 1.14.1 (`https://skyhook-io.github.io/helm-charts`) |
| Radar | v1.14.1 |
| Namespace | `radar` |
| UI | https://radar.example.com (за oauth2-proxy) |
| RBAC | Чтение + логи (чартовый read-only `ClusterRole`), без exec/port-forward/helm-write |
| Доставка | Argo CD Application `argocd/applications/radar.yaml` |

Radar — open-source Kubernetes UI одним Go-бинарём: топология, браузер ресурсов,
Helm, GitOps (Argo CD/Flux), live-трафик, метрики ворклоадов, кластерный аудит,
TLS-сертификаты и встроенный MCP-сервер для AI-агентов. Данные кластера не
уходят наружу: единственный аккаунт — `radar` ServiceAccount в кластере.

Здесь Radar служит второй (после Headlamp) панелью обзора кластера и ставится
официальным чартом под Argo CD — тем же способом, что `headlamp` и `longhorn`
(см. `argocd/README.md`).

## Файлы

| Файл | Что делает |
|---|---|
| `argocd/applications/radar.yaml` | Argo Application: официальный чарт `skyhook/radar` |
| `platform/homelab/templates/routes/radar.yaml` | UI за oauth2-proxy + secure-headers + ratelimit |
| `platform/radar/networkpolicy.yaml` | default-deny ingress + разрешения traefik и monitoring |
| `platform/monitoring/networkpolicy.yaml` | ingress из `radar` в `victoriametrics:8428` для метрик |

## Аутентификация

Radar `auth.mode` не задаёт (по умолчанию `none`): доступ к UI закрывает
forward-auth `oauth2-proxy` на Traefik, как у grafana и netdata, а в Kubernetes
Radar ходит под своим ServiceAccount с read-only `ClusterRole`. Это тот же
уровень доверия, что у остальных сервисов за прокси. Выбор правильного режима
аутентификации Radar (proxy-имперсонация vs встроенный OIDC) — отдельная
задача: issue #42.

## Установка

Все команды — на сервере из корня репозитория, после `git pull --ff-only`.

```sh
kubectl apply -f argocd/applications/radar.yaml

# Дождаться, пока Argo создаст namespace, под и слой RBAC.
kubectl -n radar get pods
argocd app get radar

kubectl apply -f platform/radar/networkpolicy.yaml

helm template platform/homelab -f platform/homelab/values.private.yaml | kubectl apply -f -
```

Порядок важен: Application создаёт namespace `radar` (`CreateNamespace=true`),
и только после этого применяются NetworkPolicy и маршрут из общего чарта.

## Проверка

```sh
kubectl -n radar get pods
kubectl -n radar logs deploy/radar --since=5m
```

Публичный маршрут без авторизации отдаёт `302` на форму Zitadel:

```sh
curl --resolve radar.${DOMAIN}:443:<node1-ip> \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://radar.${DOMAIN}/
```

После логина в oauth2-proxy — UI Radar на https://radar.example.com/.
Gatus проверяет `http://radar.radar.svc.cluster.local/api/health` из
namespace `monitoring` (правка `apps/gatus/config/config.yaml` плюс
`kubectl apply -k apps/gatus/` сама перезапускает под: ConfigMap с конфигом
собирается с хэшем содержимого).

## Права

Чарт по умолчанию создаёт `ClusterRole` с **read-only** доступом к типовым
ресурсам (workloads, networking, config, storage, HPAs, ServiceAccounts, Nodes,
Namespaces, Events) плюс чтение под-логов. Дополнительные возможности
включаются значениями `rbac.*` в `argocd/applications/radar.yaml` и требуют
более широких прав:

| Возможность | Значение | Здесь |
|---|---|---|
| Логи подов | `rbac.podLogs: true` | включено (дефолт) |
| Секреты в списке | `rbac.secrets: true` | выключено |
| Терминал / debug-поды | `rbac.podExec: true` | выключено |
| Port-forward | `rbac.portForward: true` | выключено |
| Запись Helm | `rbac.helm: true` | выключено |
| Просмотр RBAC-объектов | `rbac.viewRBAC: true` | выключено |
| Просмотр webhook-конфигов | `rbac.viewWebhooks: true` | выключено |

Включать `podExec`/`portForward`/`helm` в этом репозитории имеет смысл только
вместе с per-user аутентификацией (issue #42), иначе любой, кто прошёл
oauth2-proxy, получает эти права.

## Метрики

`traffic.prometheusUrl` указывает на VictoriaMetrics
(`http://victoriametrics.monitoring.svc.cluster.local`), поэтому вкладка
метрик ворклоада и обзор стоимости работают без автодискавери. Автодискавери
Radar ищет well-known имена и не распознаёт сервис `victoriametrics`, поэтому
адрес задан явно. Доступ из `radar` в `monitoring` открыт точечно в
`platform/monitoring/networkpolicy.yaml` (порт 8428).

## Обновление версии

Меняем `targetRevision` (версия чарта) в `argocd/applications/radar.yaml`,
применяем `kubectl apply -f argocd/applications/radar.yaml` — Argo обновит
релиз сам (self-heal + automated sync). Для отката возвращаем версию в файле и
применяем снова. Перед апгрейдом смотреть release notes:
https://github.com/skyhook-io/radar/releases

## Удаление

```sh
kubectl -n argocd delete application radar
kubectl delete -f platform/radar/networkpolicy.yaml
kubectl delete ns radar
```
