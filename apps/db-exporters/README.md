# DB exporters

Prometheus-экспортеры для всех баз homelab: по одному маленькому поду на каждый
инстанс. Метрики забирает vmagent (job'ы `postgres`, `redis`, `mysql` в
`apps/victoria-metrics/config/vmagent/scrape.yml`) и пишет в VictoriaMetrics.

Экспортеры развёрнуты в Kubernetes (`apps/db-exporters/k8s/`), namespace
`default`.

## Почему по поду на базу

Выбран вариант «один экспортер — один инстанс»: он не трогает поды баз,
не использует beta-функцию multi-target и берёт креды из **того же Secret, что
и сама база** (дублирования паролей нет). Альтернативы и их trade-off:

- **multi-target** (один экспортер на движок) — компактнее по подам, но у
  `postgres_exporter` помечен BETA, а все пароли нужно собрать в один
  зашифрованный конфиг;
- **sidecar** (экспортер контейнером рядом с БД) — production-паттерн без
  лишних подов, но правит все DB-Deployment'ы и Service'ы и роллаутит базы.

## Состав

Тип | Под | Порт | Инстансы
---|---|---|---
PostgreSQL | `postgres-exporter` (`v0.20.1`) | 9187 | 12
Redis/Valkey | `redis-exporter` (`v1.91.1`) | 9121 | 9
MariaDB | `mysqld-exporter` (`v0.20.0`) | 9104 | 1

### PostgreSQL (12)

| Экспортер | База | Пароль |
|---|---|---|
| `authentik-postgresql-exporter` | `authentik-postgresql` | Secret `authentik`/`AUTHENTIK_POSTGRESQL_PASSWORD` |
| `dawarich-db-exporter` | `dawarich-db` | Secret `dawarich`/`POSTGRES_PASSWORD` |
| `element-db-exporter` | `element-db` | Secret `element`/`POSTGRES_PASSWORD` |
| `forgejo-db-exporter` | `forgejo-db` | Secret `forgejo`/`POSTGRES_PASSWORD` |
| `glitchtip-postgres-exporter` | `glitchtip-postgres` | Secret `glitchtip`/`POSTGRES_PASSWORD` |
| `immich-db-exporter` | `immich-db` | Secret `immich`/`DB_PASSWORD` |
| `infisical-postgres-exporter` | `infisical-postgres` | Secret `infisical`/`POSTGRES_PASSWORD` |
| `nextcloud-db-exporter` | `db` (Service nextcloud) | Secret `nextcloud`/`POSTGRES_PASSWORD` |
| `paperless-db-exporter` | `paperless-db` | Secret `paperless`/`POSTGRES_PASSWORD` |
| `postgres-db-exporter` | `postgres-db` | Secret `postgres`/`POSTGRES_PASSWORD` |
| `sure-db-exporter` | `sure-db` | литерал `postgres` (как в самом DB-Deployment) |
| `zitadel-postgres-exporter` | `zitadel-postgres` | Secret `zitadel`/`POSTGRES_ADMIN_PASSWORD` |

Креды задаются через `DATA_SOURCE_URI` / `DATA_SOURCE_USER` / `DATA_SOURCE_PASS`
(без сборки DSN, чтобы спецсимволы в пароле не ломали подключение).

### Redis/Valkey (9)

`dawarich-redis`, `element-redis`, `glitchtip-valkey`, `immich-valkey`,
`infisical-redis`, `nextcloud-redis` (Service `redis`), `paperless-broker`,
`seafile-redis`, `sure-redis` — все без аутентификации, экспортеру нужен только
`REDIS_ADDR`.

### MariaDB (1)

`seafile-db-exporter` → `seafile-db:3306`, пользователь `root`, пароль из Secret
`seafile`/`INIT_SEAFILE_MYSQL_ROOT_PASSWORD` (через `MYSQLD_EXPORTER_PASSWORD`).

## Развёртывание

```sh
kubectl apply -f apps/db-exporters/k8s/
```

Проверка, что все экспортеры живы:

```sh
kubectl get pods -l 'app in (dawarich-db-exporter,seafile-db-exporter)'
```

Состояние целей в VictoriaMetrics (ожидаем `1` для всех инстансов):

```sh
kubectl exec deploy/victoriametrics -- wget -qO- \
  'http://127.0.0.1:8428/api/v1/query?query=up{job=~"postgres|redis|mysql"}'
```

Экспортер, вернувший `pg_up 0`/`mysql_up 0` при `up 1`, означает, что сам
экспортер жив, но не может подключиться к базе — смотреть его логи:

```sh
kubectl logs deploy/dawarich-db-exporter
```
