# namespaces

Юнит для namespace'ов, которые не может объявить юнит-владелец. Остальные
живут рядом со своим приложением, в `manifests/namespace.yaml` юнита: владелец
и его namespace читаются вместе.

## Правило

Namespace объявляется в юните, чьи объекты в нём живут. Исключение одно:
юнит, который применяет только внешний чарт, объявить рядом ничего не может —
у него нет своего каталога в репозитории.

## Что здесь и почему

Все десять — операторские namespace'ы, чьи юниты ставятся чартом из чужого
репозитория:

| namespace | юнит |
|---|---|
| `cnpg-system`, `databases` | `cloudnative-pg` |
| `elastic-system` | `elastic-operator` |
| `grafana-operator` | `grafana-operator` |
| `local-path-storage` | `local-path-provisioner` |
| `longhorn-system` | `longhorn` |
| `mariadb-system` | `mariadb-operator` |
| `vault` | `vault` |
| `vault-secrets-operator` | `vault-secrets-operator` |
| `victoria-metrics-operator` | `victoria-metrics-operator` |

У каждого в `spec.sources` два источника: чарт из upstream и `$values` с
`ref: values`. Argo не применяет манифесты из источника с `ref` — этот
источник даёт только значения, — поэтому положить рядом `namespace.yaml`
некуда.

`databases` — namespace кластера `shared`, а не оператора: кластеры и базы
лежат в `platform/cnpg/`, который под Argo не стоит (#902). Пока тот каталог
применяется руками, namespace берёт оператор, который этими кластерами
управляет.

Чтобы вернуть любой из них юниту-владельцу, нужно добавить в его Application
третий источник — каталог `clusters/casa/<юнит>/manifests` из этого
репозитория. Argo применяет манифесты всех источников вместе, и Namespace
окажется раньше остальных kind'ов в рамках одного sync. Дальше namespace
переезжает в `manifests/namespace.yaml` юнита и удаляется отсюда. Перенос идёт
одним коммитом: пока объявление есть в обоих местах, root падает на
`FailOnSharedResource`.

## Чего юнит не владеет

- `argocd` — namespace, в котором работает Argo. Создаётся Helm при установке,
  юнит не может быть применён раньше, чем существует.
- `kube-system`, `kube-public`, `kube-node-lease`, `default` — создаёт kubelet.
- `k0s-autopilot`, `trivy-system` — addon'ы k0s, ставятся самим k0s.

## Почему prune выключен

`automated.prune: false`. Удаление namespace из git **не удаляет** namespace
в кластере: приложение уходит в `OutOfSync` и ждёт. Обратное включение —
ручное действие.

Это осознанно. 2026-10-10 prune у root унёс 14 namespace и 22 приложения
(`docs/incidents/0009-applications-and-namespaces-recreated.md`). Внутри
namespace'а может быть state — `Cluster` CNPG со своим PVC, — и prune
удалит его вместе с базой.

В Flux то же делает `spec.prune: false` на `Kustomization` плюс
`deletionPolicy: Orphan`, чтобы удаление объекта тоже не унесло namespace.