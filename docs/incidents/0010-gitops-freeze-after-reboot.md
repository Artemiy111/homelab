# 0010 — Zitadel убит своей startup-пробой, Deployment Forgejo удалён через Argo, GitOps стоял час

Дата: 2026-10-16
Статус: устранено, действия открыты
Среда: одноузловой k0s v1.36.3, Argo CD 10.9.1, Vault 2.0.4, Forgejo 16

## Сводка

Перезагрузка сервера в 09:13:30 UTC запустила 70+ подов одновременно. На ноде с
27,8 ГБ памяти часть подов не влезла в расписание, а Vault был распечатан
вручную только через 20 минут — всё это время Vault Secrets Operator не мог
выдать секреты. Zitadel после рестарта не вышел из `startupProbe`: в манифесте
не задан `timeoutSeconds`, то есть работал дефолт **1 секунда**, а `exec`-проба
через kubelet и containerd на нагруженной ноде в неё не укладывается. Под
убивался каждые 5 минут (11 рестартов подряд), `id.biplane.casa` отдавал `503`.
Из-за этого init-контейнер `configure-gitea` в Forgejo — он синхронизирует
OAuth-провайдера с Zitadel — падал, и Forgejo не стартовал. В этот момент
Deployment'ы `forgejo` и `forgejo-runner` были удалены через UI Argo CD, и
вернуть их стало некому: Argo читает git из того же Forgejo. Все 76 Application
перешли в `Unknown` с `ComparisonError`, self-heal и prune остановились —
кластер остался без GitOps на час. Восстановление потребовало применить
Deployment Forgejo вне GitOps; процедуры для этого в репозитории не было.

## Влияние

- **Zitadel недоступен ~63 минуты** (с перезагрузки до 10:18:24 UTC), вместе с
  ним — любой вход через OIDC и всё, что за `oauth2-proxy`.
- **Forgejo недоступен ~68 минут** (до 10:21:48 UTC). Вместе с ним был
  недоступен git для Argo.
- **GitOps заморожен ~60 минут** (09:22 → 10:22:29 UTC): 76 Application в
  `Unknown`, сравнение, self-heal и prune не работают. Приложения при этом не
  удалялись: при `Unknown` Argo не выполняет prune.
- **Удалено 7 объектов через API Argo CD**: `Deployment forgejo` (4 вызова),
  `Deployment forgejo-runner`, два пода (`element-synapse`, `oauth2-proxy`).
  Поды удалять безопасно — ReplicaSet создаёт новые; Deployment'ы восстанавливать
  было нечем.
- **Данные не пострадали.** PVC `forgejo-data` на `longhorn-retain` — `Bound`,
  БД `forgejo` в CNPG `shared` — `Cluster in healthy state`, секреты выдан
  Vault. Forgejo поднялся на тех же данных и той же базе.
- **Вторичные жертвы того же окна**: `oauth2-proxy` и `radar` (503 на OIDC
  discovery), `element-synapse` (свой дефект, не связанный с перезагрузкой, см.
  ниже), `onlyoffice` и `structurizr` (упираются в лимиты на нагруженной ноде).

## Временная шкала

Время UTC. Локальное время сервера — UTC+5.

| Время | Событие |
|---|---|
| 09:13:30 | Перезагрузка сервера (`uptime -s`) |
| 09:15 — 09:20 | `FailedScheduling: 0/1 nodes are available: 1 Insufficient memory` у части подов: `victoriametrics`, `nextcloud`, `paperless`, `rustfs`, `seafile`, `structurizr`, `sure`, `uptime-kuma`, `forgejo` |
| 09:17 — 09:34 | Vault запечатан: VSO пишет `Failed to get Vault auth login: … connection refused`; `VaultStaticSecret` в `forgejo` не синхронизированы |
| 09:19 — 09:28 | Под `forgejo`: `Back-off restarting failed container configure-gitea` |
| 09:22 | Argo теряет git: у всех Application `ComparisonError`, `failed to list refs: dial tcp 192.168.1.254:2222: connect: no route to host` |
| 09:26:20 | `ApplicationService/Sync` для `forgejo`: `revision: v16.0.1`, ограничен `resources: Deployment forgejo` |
| **09:26:46 — 09:26:47** | **4 × `ApplicationService/DeleteResource`: `Deployment forgejo`** — события `application/forgejo: admin deleted resource apps/Deployment 'forgejo'` |
| 09:34:03 | Vault распечатан вручную, `HA Mode: active` |
| **09:41:20** | **`DeleteResource`: `Deployment forgejo-runner`** (`application/forgejo-extras`) |
| 09:42:11 | `DeleteResource`: под `element-synapse-7f65fb7989-rsn4g` (`force: true`) |
| 09:42:59 | `DeleteResource`: под `oauth2-proxy-c9d588cd-7fw9j` |
| 10:04:32 | Хотфикс: Deployment `forgejo` применён вручную — `helm template` чарта `v16.0.1` с `values.yaml` из репозитория, `kubectl apply --server-side` |
| 10:04 — 10:17 | Init `configure-gitea` падает с `Failed to initialize OpenID Connect Provider with name 'zitadel' … 503`: Forgejo ждёт Zitadel |
| 10:17:30 | Хотфикс: `startupProbe.timeoutSeconds: 30` у `zitadel` и `zitadel-login` |
| 10:17:38 → 10:18:24 | Новые поды обоих: `1/1 Running` через 46 секунд, цикл рестартов прекратился |
| 10:21:07 | `configure-gitea` проходит, `forgejo` стартует |
| 10:21:48 | `forgejo` — `1/1 Running`, git доступен для Argo |
| 10:22:29 | Argo сам пересоздаёт `forgejo-runner` из git — GitOps вернулся |
| 10:26:08 | Фикс в git: PR #1132, squash `62332f08` (issue #1131 закрыт после проверки) |
| 10:29 | Все Application снова `Synced/Healthy` |

## Первопричина

Установлено:

- **`startupProbe` без `timeoutSeconds` — мина замедленного действия.** Дефолт
  Kubernetes равен 1 секунде, а проба здесь — `exec`. Exec выполняется через
  kubelet и containerd и на ноде, где одновременно стартуют 70+ подов, регулярно
  занимает больше секунды: проба не проходит ни разу, `failureThreshold: 30` ×
  `periodSeconds: 10` даёт 5 минут на попытки, после чего kubelet убивает
  контейнер — и цикл повторяется бесконечно. В том же манифесте у `liveness` и
  `readiness` стоит `timeoutSeconds: 30`, то есть пропуск выглядит случайным.
  Тот же пропуск есть ещё в 68 блоках `startupProbe` (66 файлов юнитов): это не
  единичная опечатка, а
  отсутствие политики. Инциденты [0005](0005-nodefs-disk-pressure-eviction-loop.md)
  и [0006](0006-disk-pressure-ci-outage.md) уже фиксировали `probe-timeout` по
  всем приложениям при перегрузке ноды, но урок не превратился в правило.
- **Init-контейнер, зависящий от внешней системы, делает её недоступность
  отказом старта.** `configure-gitea` выполняет миграцию, создание админа и
  **синхронизацию OAuth-провайдера с Zitadel**. Пока IdP отдаёт 503, под Forgejo
  не стартует — хотя OIDC нужен Forgejo только для входа и сама синхронизация
  настроек не является условием работы сервиса. Один шаг «привести настройки в
  соответствие» поставлен в критический путь старта.
- **GitOps-источник живёт внутри управляемого кластера.** Argo читает git с
  Forgejo, а Forgejo — workload, которым управляет тот же Argo. Любое событие,
  убивающее кластер целиком, одновременно убивает и источник, и механизм
  восстановления. Выхода вне этой петли в репозитории не описано: `bootstrap/`
  содержит `argocd-values.yaml` и `root.yaml` (установка Argo и root), но не
  процедуру «поднять Forgejo без Argo». Именно этот пробел превратил ручной
  перезапуск в час простоя.
- **Ручной unseal Vault — 20 минут окна, в котором кластер не может подняться.**
  Vault распечатывается вручную (shamir), VSO без него не выдаёт ни один секрет,
  а Forgejo без секретов (`forgejo-db`, `forgejo-admin`, `forgejo-oidc`) не
  стартует. Это уже отслеживается как #676, но цена видна только в такой аварии.
- **Одномоментный старт всех подов на одном узле.** `requests` 82–86 % памяти от
  27,8 ГБ, `limits` 345–363 %; PriorityClass нет, порядок старта случаен, и
  критичные компоненты (Vault, Argo, CNPG, cert-manager) стартуют в общей
  очереди.
- **Удаление Deployment'а через UI Argo неотличимо от «перезапустить», но
  необратимо при недоступном git.** В UI нет «restart»: есть Delete. Удаление
  пода безопасно (ReplicaSet создаёт новый — так и поступили с `element-synapse`
  и `oauth2-proxy`), удаление Deployment'а перекладывает пересоздание на Argo —
  то есть на git, который в этот момент был недоступен.

Не установлено:

- Почему первый `configure-gitea` после перезагрузки (09:19–09:28) падал: логи
  того пода удалены вместе с ReplicaSet. По времени это совпадает с
  запечатанным Vault, но подтвердить можно только косвенно — события
  `VaultClientConfigError` в те же минуты.
- Почему Zitadel, будучи готовым (`/app/zitadel ready` возвращал 0), ни разу не
  проходил `startupProbe`: проба идёт от kubelet, и её таймаут нигде не
  логируется, кроме сообщения о падении пробы.

## Что сработало

- **При `Unknown` Argo не выполняет prune.** За час заморозки в кластере не
  исчезло ничего лишнего — в отличие от [0009](0009-applications-and-namespaces-recreated.md),
  где то же окно закончилось массовым удалением ресурсов.
- **Данные уцелели, и это проверялось за три команды:** PVC `forgejo-data` —
  `Bound`, CNPG `shared` — `Cluster in healthy state`, `VaultStaticSecret` —
  `Ready=True`. Вывод «Forgejo можно вернуть, не хватает одного Deployment»
  опирался на состояние хранилища, а не на догадку.
- **Ручное восстановление из тех же источника и значений.** `helm template`
  того же чарта (`v16.0.1`) с `values.yaml` из репозитория дал объект, идентичный
  тому, что создал бы Argo: до применения проверен `--dry-run=server`, после
  возврата git синхронизация не потребовала ни рестарта, ни правок.
- **Метрики отделили последствия перезагрузки от латентных дефектов.**
  `kube_pod_container_status_restarts_total` и
  `kube_deployment_status_replicas_unavailable` в VictoriaMetrics показали, что
  `element-synapse` до перезагрузки был здоров — 0 рестартов за 7 дней. Это
  сразу исключило его из последствий аварии и увело разбор в сторону старого
  домена в базе.
- **Логи `argocd-server` назвали автора удаления.** `grpc.request.content` в
  `ApplicationService/DeleteResource` содержит app, kind, имя и флаг `orphan`,
  а `ResourceDeleted` — время и имя объекта. Без них «кто-то удалил Deployment»
  осталось бы версией.

## Уроки

- **Пропущенный `timeoutSeconds` не видит ни один гейт.** `kubeconform` и
  `kube-linter` пропускают его молча, в диффе он невидим, а проявляется только
  отказом старта на перегруженной ноде. Это повод для проверки политики, а не
  для разовой правки: правил пробы в двух юнитах, а манифестов с тем же
  пропуском — 68.
- **`exec` — дорогая проба.** Она поднимает процесс через kubelet и containerd,
  то есть измеряет ещё и загрузку ноды. Там, где хватает `httpGet`, `exec`
  добавляет отказу старта лишнюю зависимость.
- **У GitOps должен быть выход за свои пределы.** Пока источник git — workload в
  том же кластере, любая авария уровня ноды оставляет себе ровно один сценарий:
  ручное восстановление по памяти. Внешний git или документированная процедура
  внеполосного восстановления — не улучшение, а условие.
- **Init-контейнер — часть контракта доступности.** Если он ходит в чужой сервис
  за настройками, чужой сервис становится условием старта. Такие шаги либо
  терпимы к недоступности, либо не должны быть в init.
- **ConfigMap по ссылке в env не запускает rollout.** Домен в `homelab-config`
  менялся, а поды продолжали жить со старым значением, пока их не перезапустили:
  расхождение «что в конфиге» и «что у процесса» копилось молча. При первой же
  перезагрузке оно стало отказом старта (`element-synapse`, отдельный дефект, ни
  в 0009, ни здесь не исправлен).
- **Удаление пода и удаление Deployment'а — разные по обратимости действия.**
  Первое делает ReplicaSet, второе — GitOps. В UI Argo CD они выглядят
  одинаково.

## Действия

| Действие | Issue |
|---|---|
| `startupProbe.timeoutSeconds: 30` у `zitadel` и `zitadel-login` | #1131 (сделано, PR #1132) |
| Остальные `startupProbe` без `timeoutSeconds` и отказ от `exec` там, где хватает `httpGet` | кандидат |
| Процедура внеполосного восстановления Forgejo при недоступном git — в RUNBOOK юнита, с ADR про bootstrap-цикл | кандидат |
| Авто-unseal Vault: выбрать способ и обосновать | #676 |
| Алерт на sealed-состояние Vault | #675 |
| PriorityClass и порядок старта критичных компонентов после перезагрузки | #1136 |
| Ресурсы `onlyoffice` и `structurizr`: упираются в лимиты памяти и CPU на нагруженной ноде | #1130 (частично) |
| `element-synapse`: старый домен `biplane.v6.rocks` в базе при конфиге `biplane.casa` | #877 |
| Включить или обоснованно отказаться от аудита API-сервера | #927 |
