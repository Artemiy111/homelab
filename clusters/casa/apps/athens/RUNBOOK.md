# Athens: эксплуатация

## Подключение клиента

В job'е (или на хосте, где есть доступ к сервису) выставить:

```
GOPROXY=http://athens.athens.svc.cluster.local
GOSUMDB=sum.golang.org http://athens.athens.svc.cluster.local/sumdb/sum.golang.org
```

С хоста (Ansible-сборка `vals` из `cli_tools`) Athens доступен по внешнему
маршруту Traefik:

```
GOPROXY=https://goproxy.<домен>
GOSUMDB=sum.golang.org https://goproxy.<домен>/sumdb/sum.golang.org
```

## Добавление модулей

Ничего добавлять не нужно: модуль кэшируется при первом обращении. Прогреть
кэш заранее можно ручным запросом, например:

```
GOPROXY=http://athens.athens.svc.cluster.local \
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
     sh -c 'GOPROXY=http://athens.athens.svc.cluster.local \
       GOSUMDB="sum.golang.org http://athens.athens.svc.cluster.local/sumdb/sum.golang.org" \
       go install golang.org/x/tools/cmd/stringer@v0.50.0'
   ```

   В логах Athens виден запрос к upstream.
3. Повторить в свежем поде — модуль отдаётся из хранилища, в логах Athens нет
   обращения к `proxy.golang.org`.
4. Симуляция падения upstream: временно сломать `GOPROXY` в конфиге Athens (или
   закрыть egress) — уже закэшированный модуль всё равно отдаётся.
