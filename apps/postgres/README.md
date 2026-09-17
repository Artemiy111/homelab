# PostgreSQL playground

Тестовый PostgreSQL с веб-интерфейсом [pgweb](https://sosedoff.github.io/pgweb/).
База не публикует порт `5432` на хосте: к ней можно подключиться из pgweb или
из терминала через Docker Compose.

## Запуск

```sh
bash scripts/bootstrap-platform.sh postgres
```

pgweb откроется по адресу `https://postgres.example.com/` и сразу
подключится к базе `playground`. Логин и пароль HTTP Basic Auth находятся в
секретах сервиса (`PGWEB_AUTH_USER` и `PGWEB_AUTH_PASS`).

## Вход в PostgreSQL из терминала

Находясь в каталоге `postgres`, можно сразу открыть `psql` внутри контейнера:

```sh
docker compose exec db sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
```

Или сначала войти в shell контейнера, а затем запустить `psql`:

```sh
docker compose exec db sh
psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
```

Несколько полезных команд внутри `psql`:

```text
\l         список баз данных
\dt        список таблиц
\q         выход
```

Одноразовый SQL-запрос без интерактивного входа:

```sh
docker compose exec db sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT version();"'
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
`apps/victoria-metrics/config/vmagent/scrape.yml`.

Проверка:

```sh
kubectl logs deploy/postgres-db -c postgres-exporter
kubectl exec deploy/postgres-db -c postgres-exporter -- wget -qO- localhost:9187/metrics | head
```

## Остановка

```sh
docker compose down
```

Эта команда удаляет контейнеры и сеть проекта, но сохраняет данные базы на
хосте.
