# Radar (Kubernetes UI)

| | |
|---|---|
| Чарт | `radar` 1.14.1 (`https://skyhook-io.github.io/helm-charts`) |
| Radar | v1.14.1 |
| Namespace | `radar` |
| UI | https://radar.example.com (собственный OIDC-вход через Zitadel) |
| RBAC | Права пользователя — по его Kubernetes-RBAC (имперсонация) |
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
| `argocd/applications/radar.yaml` | Argo Application: официальный чарт `skyhook/radar`, `auth.mode=oidc`; issuer, clientID и redirectURL заданы в `valuesObject` |
| `platform/radar/route.yaml` | Маршрут: secure-headers + ratelimit, без oauth2-proxy |
| `platform/radar/vso-radar.serviceaccount.yaml` | ServiceAccount для External Secrets Operator |
| `platform/radar/vso-radar.vaultauth.yaml` | `VaultAuth` с ролью `radar` из Vault |
| `platform/radar/radar-oidc.vaultstaticsecret.yaml` | `VaultStaticSecret` `kv/radar/oidc` |
| `platform/radar/networkpolicy.yaml` | default-deny ingress + разрешения traefik и monitoring |
| `platform/monitoring/networkpolicy.yaml` | ingress из `radar` в `victoriametrics:8428` для метрик |
| `terraform/zitadel/applications.tf` | Приложение `radar` в Zitadel |
| `terraform/vault/roles.tf`, `policies/own.tf` | Роль и политика `app/radar` |

## Аутентификация

`auth.mode=oidc`: Radar сам ходит в Zitadel и **имперсонирует** пользователя в
Kubernetes. Поэтому права определяет RBAC конкретного человека, а не общий
ServiceAccount. Схема по шагам:

| Шаг | Где |
|---|---|
| Приложение OIDC в Zitadel | `terraform/zitadel/applications.tf` (`zitadel_application_v2.radar`) |
| Claim `role` (`admin`/`user`) | `terraform/zitadel/actions.tf` |
| `cluster-admin` для группы `oidc:admin` | `platform/headlamp/headlamp-admins.clusterrolebinding.yaml` |
| clientSecret, redirectURL | Vault `kv/radar/oidc` |
| clientID, issuer | `valuesObject` в `argocd/applications/radar.yaml` |
| Отдельный HMAC-ключ сессий | Vault `kv/radar/oidc`, ключ `auth-secret` |

Группы приходят из claim `role` с префиксом `oidc:` — получается ровно та же
группа `oidc:admin`, что у Headlamp, поэтому один `ClusterRoleBinding` покрывает
оба UI. Отдельный OIDC-клиент у Radar обязателен: сессия Radar хранит
`id_token` пользователя, и переиспользование клиента, которому доверяет
apiserver, превратило бы утечку сессии в доступ к API-серверу.

Привязка только по группе, не по пользователю: имя Radar берёт из claim `email`,
apiserver — из `sub`, поэтому `kind: User` у них не совпадёт.

### Почему с маршрута убран oauth2-proxy

У grafana, netdata и VM oauth2-proxy остаётся. У Radar — нет:

- **Back-channel logout сломался бы.** Zitadel шлёт `POST` на
  `/auth/backchannel-logout` без cookie прокси; forward-auth ответил бы `401`,
  и отзыв сессии при отключении пользователя в Zitadel не сработал бы.
- **Двойной вход.** Прокси и Radar спрашивали бы Zitadel раздельно.
- **Ложное чувство защиты.** Прокси проверяет факт входа, а не права. Права
  выдаёт RBAC — и Radar, и Headlamp получают их одинаково.

### Цена решения

`auth.mode != none` расширяет `ClusterRole` ServiceAccount'а Radar:

| Что добавляет чарт | Зачем |
|---|---|
| `impersonate` на `users`, `groups` | вызовы от имени пользователя |
| `create` на `subjectaccessreviews` | проверка, что ему можно |
| чтение `secrets` по всему кластеру | включено автоматически, кэш перепроверяется per-user |
| чтение RBAC- и webhook-объектов | включено автоматически, кэш перепроверяется per-user |

Kubernetes не умеет ограничивать `impersonate` подмножеством пользователей:
**токен этого ServiceAccount эквивалентен cluster-admin.** Граница — только
NetworkPolicy в `platform/radar/networkpolicy.yaml` (ingress разрешён traefik и
monitoring) и отсутствие иных путей до пода.

Побочный эффект: у человека с `role=admin` появляется второй путь к
cluster-admin — Headlamp через apiserver, Radar через имперсонацию.

## Установка

Все команды — на сервере из корня репозитория, после `git pull --ff-only`.
Сначала Terraform (Zitadel-приложение и роль Vault), затем кластер.

```sh
cd terraform/zitadel && terraform apply
cd ../vault && terraform apply
```

ClientSecret нового приложения в state не попадает — Zitadel отдаёт его только
в консоли. Положить в Vault `kv/radar/oidc` (v2) два ключа:

| Ключ | Откуда | Кто читает |
|---|---|---|
| `client-secret` | clientSecret приложения Radar в Zitadel | `RADAR_OIDC_CLIENT_SECRET` |
| `auth-secret` | случайная строка, например `openssl rand -base64 32` | `RADAR_AUTH_SECRET` |

Имена ключей — дефолты чарта (`auth.existingSecretKey` и
`auth.oidc.clientSecretKey`); задавать их в Application не нужно. Оба секрета
приходят в один Secret `radar-auth`.

`clientID` в Vault не нужен: Radar берёт его из `--auth-oidc-client-id`, то
есть из `valuesObject` в `argocd/applications/radar.yaml`. В Helm release он
попадает открытым текстом, но clientID — публичный идентификатор, не секрет;
секретом является только `client-secret`.

`client-secret` и `auth-secret` читаются Radar'ом только при старте, поэтому при
ротации в Vault под пересоздаётся — за это отвечает `rolloutRestartTargets` в
`radar-oidc.vaultstaticsecret.yaml`.

Затем Application и остальное:

```sh
kubectl apply -f argocd/applications/radar.yaml

# Дождаться, пока Argo создаст namespace, под и слой RBAC.
kubectl -n radar get pods
argocd app get radar

kubectl apply -f platform/radar/
helm template platform/homelab | kubectl apply -f -
```

Порядок важен: Application создаёт namespace `radar` (`CreateNamespace=true`),
и только после этого применяются остальные манифесты и маршрут из общего чарта.
Секреты в `radar-auth` должны появиться **до** синка: иначе Radar стартует без
`RADAR_OIDC_CLIENT_SECRET`.

## Проверка

```sh
kubectl -n radar get vaultstaticsecret radar-oidc
kubectl -n radar get pods
kubectl -n radar logs deploy/radar --since=5m | grep -E "\[oidc\]|\[auth\]"
```

В логах при старте ожидаются строки `[oidc] Requesting scopes: [openid profile
email]`, `[oidc] RP-Initiated Logout enabled` и `[oidc] Backchannel Logout
enabled`.

Публичный маршрут без сессии отдаёт `401` (не `302` — вход теперь внутри Radar):

```sh
curl --resolve radar.${DOMAIN}:443:<node1-ip> \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://radar.${DOMAIN}/
```

После логина в Zitadel — UI Radar на https://radar.example.com/. Если вход
проходит, а namespace'ов не видно, — не хватает RBAC-привязки: Radar
показывает только то, что пользователю разрешено, и делает это fail-closed.
Проверить глазами:

```sh
kubectl auth can-i list pods -n radar --as=<email> --as-group=oidc:admin
```

Gatus проверяет `http://radar.radar.svc.cluster.local/api/health` из namespace
`monitoring` (правка `apps/gatus/config/config.yaml` плюс `kubectl apply -k
apps/gatus/` сама перезапускает под: ConfigMap с конфигом собирается с хэшем
содержимого). `/api/health` exempt даже при включённой аутентификации.

## Права

`rbac.*` в `argocd/applications/radar.yaml` задают, что **ServiceAccount**
может, и наполняют общий кэш Radar. Права конкретного пользователя поверх этого
определяет Kubernetes RBAC, а Radar проверяет их через `SubjectAccessReview` и
имперсонирует при записи.

| Возможность | Значение | Здесь |
|---|---|---|
| Логи подов | `rbac.podLogs: true` | включено (дефолт) |
| Секреты в списке | `rbac.secrets` | чартом, при `auth.mode=oidc` |
| Просмотр RBAC-объектов | `rbac.viewRBAC` | чартом, при `auth.mode=oidc` |
| Просмотр webhook-конфигов | `rbac.viewWebhooks` | чартом, при `auth.mode=oidc` |
| Терминал / debug-поды | `rbac.podExec: true` | выключено |
| Port-forward | `rbac.portForward: true` | выключено |
| Запись Helm | `rbac.helm: true` | выключено |

Три помеченные «чартом» строки включаются автоматически и переопределить их
нельзя: под auth кэш хранит эти данные, а каждое чтение перепроверяется
правами пользователя.

`podExec`, `portForward` и `helm` включаются **своим** флагом, и операция
выполняется уже от имени пользователя. То есть они больше не выдаются всем
прошедшим вход, а требуют соответствующих прав в Kubernetes RBAC.


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
