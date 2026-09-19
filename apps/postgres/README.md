# PostgreSQL playground

Тестовый PostgreSQL с веб-интерфейсом [pgweb](https://sosedoff.github.io/pgweb/).
База не публикует порт `5432` на хосте: к ней можно подключиться из pgweb или
из терминала.

## Запуск

Разворачивается манифестами в apps/postgres/k8s/.

pgweb доступен по адресу `https://postgres.example.com/` и сразу
подключён к базе `playground`. Логин и пароль HTTP Basic Auth находятся в
секретах сервиса (`PGWEB_AUTH_USER` и `PGWEB_AUTH_PASS`).

## Работа с PostgreSQL

После подключения к базе через `psql` доступны команды:

```text
\l         список баз данных
\dt        список таблиц
\q         выход
```

## Метрики

Экспортер `postgres-exporter` поднят **сайдкаром** — вторым контейнером в том
же поде `postgres-db`, рядом с базой. Поэтому он подключается к ней через
`localhost:5432` (а не по Service) и живёт ровно столько же, сколько база:
рестарт пода перезапускает обоих.

У сайдкара только `livenessProbe`, без `readinessProbe`: под Ready, только
когда готовы все контейнеры, поэтому неготовая readiness экспортера сделала бы
под базы NotReady и выкинула бы его из endpoints Service — при полностью живой
базе.

Порт `9187` объявлен в поде и продублирован в сервисе `postgres-db` (порт
`metrics`). Оттуда его скрейпит vmagent — цель `postgres-db:9187` в
`apps/victoria-metrics/k8s/vmagent.configmap.yaml`.

Проверка:

```sh
kubectl logs deploy/postgres-db -c postgres-exporter
kubectl exec deploy/postgres-db -c postgres-exporter -- wget -qO- localhost:9187/metrics | head
```
