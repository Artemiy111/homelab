# Zot

Zot — лёгкий OCI-реестр, используемый как **pull-through кэш** внешних реестров
для job'ов Forgejo Actions. Первый pull образа идёт в upstream
(`ghcr.io`, `docker.io`, `data.forgejo.org`), дальше образ отдаётся из
локального хранилища — недоступность или rate-limit внешнего реестра не ломает
пайплайн.

| | |
|---|---|
| Namespace | `zot` |
| Развёртывание | манифестами `apps/zot/k8s/` (`kubectl apply --server-side --field-manager=homelab -f`) |
| Образ | `ghcr.io/project-zot/zot:v2.1.21` (пин по тегу и дайджесту) |
| Данные | PVC `zot-data` на `longhorn` (кэш, потеря не страшна) |
| API | `http://zot.zot.svc.cluster.local` — только внутри кластера |
| Потребитель | Forgejo Runner + DinD (`apps/forgejo`) |

Кластерные образы (kubelet/containerd) через Zot **не** ходят: кэш нужен только
для CI.

## Как это работает

- Zot слушает `:5000` в контейнере (это `targetPort` Service'а), а наружу
  Service отдаёт его на стандартном порту 80. По конфигу (`configmap.yaml`)
  Zot знает upstream-реестры
  (`extensions.sync.registries`), каждый с `onDemand: true` — это и есть
  pull-through: образ скачивается при первом запросе, затем отдаётся локально.
- `http.compat: ["docker2s2"]` + `preserveDigest: true` сохраняют исходный
  формат и дайджест образов, поэтому пины раннера по дайджесту остаются
  валидными.
- `accessControl` с единственным `anonymousPolicy: ["read"]` — режим
  «anonymous-only»: анонимный pull разрешён (DinD тянет без креденшелов),
  push запрещён. Смешивать с аутентификацией нельзя: тогда Zot отдаёт 401 на
  `/v2/` для Docker-клиентов и анонимный pull ломается
  ([authn-authz](https://zotregistry.dev/v2.1.21/articles/authn-authz/)).
- Так как Zot отдаётся по http, его хост помечен `insecure-registries` в
  `apps/forgejo/k8s/runner-dind.configmap.yaml`.

## Развёртывание

```sh
kubectl apply --server-side --field-manager=homelab -f apps/zot/k8s/
kubectl -n zot get pods,pvc,svc
```

Проверка, что API жив (конфиг anonymous-only, поэтому `/v2/` отдаёт 403 — это
нормально, а pull при этом работает):

```sh
kubectl -n zot logs deploy/zot --tail=20
```

## Как подключён раннер

Метки (`runs-on`) в `apps/forgejo/k8s/runner.configmap.yaml` ссылаются на образ
**через путь кэша** (`zot.zot.svc.cluster.local/<реестр>/...`), а DinD
тянет его из Zot. Пример:

```
ubuntu-latest:docker://zot.zot.svc.cluster.local/ghcr.io/catthehacker/ubuntu@sha256:...
```

Дайджест — тот же, что у upstream.

## Ограничение: Docker Hub vs остальные реестры

Docker-демон умеет `registry-mirrors` **только для Docker Hub**. Поэтому
подменить реестр «зеркалом» для `ghcr.io`/`quay.io` нельзя — там путь кэша
указывается явно (в метках раннера, а при необходимости и в workflow'ах:
`docker pull zot.zot.svc.cluster.local/ghcr.io/<образ>`). Для `docker.io`
внутри job'ов mirror тоже не настроен: он потянул бы за собой плоский протокол
Hub, несовместимый с path-prefix раскладкой Zot. Если понадобится — делать
отдельным шагом.

## Добавление upstream-реестра

Дописать запись в `extensions.sync.registries` (`configmap.yaml`) и применить:

```json
{
  "urls": ["https://quay.io"],
  "onDemand": true,
  "tlsVerify": true,
  "preserveDigest": true,
  "content": [{ "prefix": "**", "destination": "/quay.io" }]
}
```

Для приватных upstream'ов нужен `credentialsFile` из Secret'а, а не из
ConfigMap.

## Размер кэша и очистка

Том — `longhorn`, 20Gi, без `Retain`: кэш восстановим. Zot собирает мусор
(`storage.gc`, `gcInterval: 24h`). Если том переполнится, проще увеличить PVC
или удалить `zot-data` (Zot скачает нужное заново).

## Проверка на живом стенде

1. `kubectl -n zot get pods` — под `Running`.
2. Прогнать любой workflow: job стартует, в логах Zot виден pull-through
   (`kubectl -n zot logs deploy/zot | grep -i sync`).
3. Повторный прогон или рестарт пода раннера — образ не тянется из интернета.

Первый pull каждого образа заметно медленнее (Zot качает из upstream), это
одноразовая плата.
