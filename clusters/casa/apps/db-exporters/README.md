# DB exporters

Prometheus-экспортеры для баз homelab, которые ещё не переехали в CloudNativePG:
по одному маленькому поду на каждый инстанс. Метрики забирает vmagent (job'ы
`postgres`, `redis`, `mysql` в `clusters/casa/apps/victoria-metrics/config/vmagent/scrape.yml`)
и пишет в VictoriaMetrics.

Каждый экспортер живёт в namespace своего сервиса.

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

## Что покрыто

Redis/Valkey: `dawarich-redis`, `element-valkey`, `glitchtip-valkey`,
`immich-valkey`, `infisical-redis`, `nextcloud-redis`, `paperless-broker`,
`seafile-redis`, `sure-redis` — все без аутентификации, экспортеру нужен только
`REDIS_ADDR`.

MariaDB:

- `seafile-mariadb-exporter` → `seafile-mariadb:3306` (пользователь `root`,
  пароль из Secret `seafile`/`INIT_SEAFILE_MYSQL_ROOT_PASSWORD`);
- `uptime-kuma-mariadb-exporter` → `uptime-kuma-mariadb:3306` (пользователь
  `root`, пароль из Secret `uptime-kuma-mariadb-root`/
  `INIT_UPTIME_KUMA_MARIADB_ROOT_PASSWORD`).

Эксплуатация — в `RUNBOOK.md`.
