# DB exporters

Prometheus-экспортеры для баз homelab, которые ещё не переехали в CloudNativePG:
по одному маленькому поду на каждый инстанс. Метрики забирает vmagent (job'ы
`postgres`, `redis`, `mysql` в `apps/victoria-metrics/config/vmagent/scrape.yml`)
и пишет в VictoriaMetrics.

Экспортеры развёрнуты в Kubernetes (`apps/db-exporters/k8s/`), каждый в
namespace своего сервиса.

**Базы в CloudNativePG сюда не входят.** Встроенный экспортёр instance-manager
отдаёт `/metrics` на порту `metrics` (9187) каждого пода кластера, а vmagent
находит их service discovery (job `cnpg`). Поэтому для `immich`, `dawarich`,
`zitadel`, `paperless`, `infisical`, `glitchtip`, `playground`, `authentik`,
`forgejo`, `sure`, `nextcloud` и `element` отдельных подов нет: их метрики
приходят из кластеров `immich-db`, `dawarich-db`, `zitadel-db` и `shared`
(различать базы внутри кластера нужно по `datname`).

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
Redis/Valkey | `redis-exporter` (`v1.91.1`) | 9121 | 9
MariaDB | `mysqld-exporter` (`v0.20.0`) | 9104 | 1

### Redis/Valkey (9)

`dawarich-redis`, `element-redis`, `glitchtip-valkey`, `immich-valkey`,
`infisical-redis`, `nextcloud-redis`, `paperless-broker`, `seafile-redis`,
`sure-redis` — все без аутентификации, экспортеру нужен только `REDIS_ADDR`.

### MariaDB (1)

`seafile-mariadb-exporter` → `seafile-mariadb:3306` (MariaDB-инстанс под
mariadb-operator), пользователь `root`, пароль из Secret
`seafile`/`INIT_SEAFILE_MYSQL_ROOT_PASSWORD` (через `MYSQLD_EXPORTER_PASSWORD`).

## Развёртывание

```sh
kubectl apply -f apps/db-exporters/k8s/
```

Проверка, что все экспортеры живы:

```sh
kubectl get pods -l 'app in (seafile-mariadb-exporter,seafile-redis-exporter)'
```

Состояние целей в VictoriaMetrics (ожидаем `1` для всех инстансов):

```sh
kubectl exec deploy/victoriametrics -- wget -qO- \
  'http://127.0.0.1:8428/api/v1/query?query=up{job=~"redis|mysql"}'
```

Экспортер, вернувший `mysql_up 0` при `up 1`, означает, что сам
экспортер жив, но не может подключиться к базе — смотреть его логи:

```sh
kubectl logs deploy/seafile-mariadb-exporter
```
