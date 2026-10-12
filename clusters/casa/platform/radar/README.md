# Radar (Kubernetes UI)

URL: `https://radar.example.com`

Radar — open-source Kubernetes UI одним Go-бинарём: топология, браузер ресурсов,
Helm, GitOps (Argo CD/Flux), live-трафик, метрики ворклоадов, кластерный аудит,
TLS-сертификаты и встроенный MCP-сервер для AI-агентов. Данные кластера не
уходят наружу: единственный аккаунт — `radar` ServiceAccount в кластере.

Здесь Radar служит второй (после Headlamp) панелью обзора кластера и ставится
официальным чартом под Argo CD — тем же способом, что `headlamp` и `longhorn`
(см. `docs/runbooks/argocd.md`).

## Аутентификация

`auth.mode=oidc`: Radar сам ходит в Zitadel и **имперсонирует** пользователя в
Kubernetes. Поэтому права определяет RBAC конкретного человека, а не общий
ServiceAccount. Схема по шагам:

| Шаг | Где |
|---|---|
| Приложение OIDC в Zitadel | `infra/terraform/zitadel/applications.tf` (`zitadel_application_v2.radar`) |
| Claim `role` (`admin`/`user`) | `infra/terraform/zitadel/actions.tf` |
| `cluster-admin` для группы `oidc:admin` | `clusters/casa/platform/headlamp/headlamp-admins.clusterrolebinding.yaml` |
| clientSecret, redirectURL | Vault `kv/radar/oidc` |
| clientID, issuer | `valuesObject` Application |
| Отдельный HMAC-ключ сессий | Vault `kv/radar/oidc`, ключ `auth-secret` |

Группы приходят из claim `role` с префиксом `oidc:` — получается ровно та же
группа `oidc:admin`, что у Headlamp, поэтому один `ClusterRoleBinding` покрывает
оба UI. Отдельный OIDC-клиент у Radar обязателен: сессия Radar хранит
`id_token` пользователя, и переиспользование клиента, которому доверяет
apiserver, превратило бы утечку сессии в доступ к API-серверу.

Привязка только по группе, не по пользователю: имя Radar берёт из claim `email`,
apiserver — из `sub`, поэтому `kind: User` у них не совпадёт.

### Почему с маршрута убран oauth2-proxy

У grafana и VM oauth2-proxy остаётся. У Radar — нет:

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
NetworkPolicy этого юнита (ingress разрешён traefik и
monitoring) и отсутствие иных путей до пода.

Побочный эффект: у человека с `role=admin` появляется второй путь к
cluster-admin — Headlamp через apiserver, Radar через имперсонацию.

## Права

`rbac.*` в `Application` задают, что **ServiceAccount**
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
`clusters/casa/platform/monitoring/networkpolicy.yaml` (порт 8428).

Установка, проверка, обновление версии и удаление — в `RUNBOOK.md`.
