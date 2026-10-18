# PostgreSQL playground

Тестовый PostgreSQL с веб-интерфейсом [pgweb](https://sosedoff.github.io/pgweb/).
Порт `5432` наружу не публикуется: к базе ходят через pgweb или из терминала
внутри кластера.

## Хранилище

База — PostgreSQL в общем кластере CNPG `shared` (namespace `databases`,
эндпоинт `shared-rw.databases.svc.cluster.local:5432`). Роль `playground`, база
`playground` и NetworkPolicy объявлены в `platform/casa/cnpg/`; пароль роль берёт из
Secret'а `postgres-db-auth`, а pgweb — из своего Secret'а `postgres`
(ключ `POSTGRES_PASSWORD`), поэтому в `PGWEB_DATABASE_URL` менялся только хост.
Легаси-инстанс `postgres-db` с hostPath-каталогом снят, данные перенесены
дампом.

## Метрики

Метрики базы отдаёт встроенный экспортёр CNPG; vmagent находит под кластера
service discovery (job `cnpg`). Отдельный таргет и сайдкар-экспортёр больше не
нужны.

Эксплуатация — в `RUNBOOK.md`.
