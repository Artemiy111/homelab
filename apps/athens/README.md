# Athens

Athens — прокси Go-модулей по официальному протоколу **`GOPROXY`**, используемый
как **pull-through кэш** внешних модулей для CI и сборок. Первый запрос модуля
идёт в upstream (`proxy.golang.org`), дальше модуль отдаётся из локального
хранилища — недоступность внешнего прокси или GitHub не ломает сборку.

| | |
|---|---|
| Namespace | `athens` |
| Развёртывание | kustomize `apps/athens/` (`kubectl apply -k`) |
| Образ | `gomods/athens:v0.18.1` (пин по тегу и дайджесту, amd64) |
| Данные | PVC `athens-data` на `longhorn` (кэш, потеря не страшна) |
| API | `http://athens.athens.svc.cluster.local:3000` — внутри кластера |
| Маршрут | `https://goproxy.<домен>` (Traefik, чарт `platform/homelab`) |
| Потребитель | CI (`actions/setup-go`), сборка Go на хосте |

## Как это работает

- Athens реализует протокол `GOPROXY`: `GET /<module>/@v/list`, `<ver>.info`,
  `.mod`, `.zip`. Клиент просто указывает `GOPROXY` на Athens.
- `DownloadMode = "sync"` — pull-through: при первом запросе модуль скачивается
  и сохраняется в хранилище, дальше отдаётся из него.
- `GoBinaryEnvVars = ["GOPROXY=https://proxy.golang.org"]` — внутренний `go`
  самого Athens тянет модули через публичный Go-прокси, а не через VCS/git;
  это убирает зависимость от `github.com` и git-клонирования.
- `SumDBs = ["https://sum.golang.org"]` — Athens проксирует checksum-базу, чтобы
  клиент мог проверять контрольные суммы через сам Athens (см. ниже).
- `StorageType = "disk"` — модули лежат на PVC Longhorn; потеря тома означает
  лишь повторную загрузку из upstream.
- Athens не умеет fine-grained ACL, а basic auth глобальный и светится в логах,
  поэтому сервис доступен только внутри кластера и без аутентификации.

## Развёртывание

```sh
kubectl apply -k apps/athens/
kubectl -n athens get pods,pvc,svc
```

## Как подключить клиента

В job'е (или на хосте, где есть доступ к сервису) выставить:

```
GOPROXY=http://athens.athens.svc.cluster.local:3000
GOSUMDB=sum.golang.org http://athens.athens.svc.cluster.local:3000/sumdb/sum.golang.org
```

`GOSUMDB` в формате `<имя> <url>` заставляет `go` проверять контрольные суммы
через Athens, а не напрямую в `sum.golang.org`; путь `/sumdb/<host>` — это и есть
sumdb-прокси Athens. Если проверка сумм не нужна (доверенная среда), достаточно
`GONOSUMDB=*`.

В проекте с `go.mod`/`go.sum` сборка тянет только зафиксированные модули и
обслуживается кэшем целиком. `go install <pkg>@latest` дополнительно спрашивает
у upstream список версий, поэтому для полностью офлайновых сборок пинить версию
(`@vX.Y.Z`) или собирать из `go.mod`.

С хоста (Ansible-сборка `vals` из `cli_tools`) Athens доступен по внешнему
маршруту Traefik (`platform/homelab/templates/routes/athens.yaml`):

```
GOPROXY=https://goproxy.<домен>
GOSUMDB=sum.golang.org https://goproxy.<домен>/sumdb/sum.golang.org
```

Маршрут без аутентификации: `go` не умеет forward auth, а `/` и `/catalog`
доступны только в LAN/Tailscale.

## Добавление модулей

Ничего добавлять не нужно: модуль кэшируется при первом обращении. Прогреть
кэш заранее можно ручным запросом, например:

```
GOPROXY=http://athens.athens.svc.cluster.local:3000 \
  go install golang.org/x/tools/cmd/stringer@latest
```

## Размер кэша и очистка

Том — `longhorn`, 1Gi, без `Retain`: кэш восстановим. Если том переполнится,
проще увеличить PVC или удалить `athens-data` (Athens скачает нужное заново).

## Проверка на живом стенде

1. `kubectl -n athens get pods,pvc,svc` — под `Running`.
2. Прогреть модуль изнутри кластера (пустой модульный кэш, образ `golang`):

   ```sh
   kubectl -n athens run athens-check --rm -it --restart=Never \
     --image=golang:1.26-alpine -- \
     sh -c 'GOPROXY=http://athens.athens.svc.cluster.local:3000 \
       GOSUMDB="sum.golang.org http://athens.athens.svc.cluster.local:3000/sumdb/sum.golang.org" \
       go install golang.org/x/tools/cmd/stringer@v0.50.0'
   ```

   В логах Athens виден запрос к upstream.
3. Повторить в свежем поде — модуль отдаётся из хранилища, в логах Athens нет
   обращения к `proxy.golang.org`.
4. Симуляция падения upstream: временно сломать `GOPROXY` в конфиге Athens (или
   закрыть egress) — уже закэшированный модуль всё равно отдаётся.
