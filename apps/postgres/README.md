# PostgreSQL playground

Тестовый PostgreSQL с веб-интерфейсом [pgweb](https://sosedoff.github.io/pgweb/).
Порт `5432` наружу не публикуется: к базе ходят через pgweb или из терминала
внутри кластера.

## Запуск

Разворачивается манифестами в `apps/postgres/k8s/`.

pgweb доступен по адресу `https://postgres.example.com/` и сразу подключён к
базе `playground`. Логин и пароль HTTP Basic Auth находятся в секретах сервиса
(`PGWEB_AUTH_USER` и `PGWEB_AUTH_PASS`).

## Хранилище

База — PostgreSQL в общем кластере CNPG `shared` (namespace `databases`,
эндпоинт `shared-rw.databases.svc.cluster.local:5432`). Роль `playground`, база
`playground` и NetworkPolicy объявлены в `platform/cnpg/`; пароль роль берёт из
Secret'а `postgres-db-auth`, а pgweb — из своего Secret'а `postgres`
(ключ `POSTGRES_PASSWORD`), поэтому в `PGWEB_DATABASE_URL` менялся только хост.
Легаси-инстанс `postgres-db` с hostPath-каталогом снят, данные перенесены
дампом.

## Работа с PostgreSQL

После подключения к базе через `psql` доступны команды:

```text
\l         список баз данных
\dt        список таблиц
\q         выход
```

## Метрики

Метрики базы отдаёт встроенный экспортёр CNPG; vmagent находит под кластера
service discovery (job `cnpg`). Отдельный таргет и сайдкар-экспортёр больше не
нужны.
