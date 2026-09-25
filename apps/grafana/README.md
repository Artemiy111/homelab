# Grafana

Grafana — единый UI для дашбордов поверх VictoriaMetrics. Сервис развёрнут в
Kubernetes (`apps/grafana/`) и доступен через Traefik кластера по адресу
`https://grafana.example.com/` за `oauth2-proxy`.

Отделён от `apps/victoria-metrics/`: Grafana — независимый слой визуализации
(свои образ, данные, секрет и маршрут), который лишь читает метрики из
VictoriaMetrics как datasource.

## Данные и доступ

- Образ `grafana/grafana:13.2.0` (зафиксирован по digest), uid/gid `1000`.
- Данные (пользователи, дашборды, алерты, аннотации) — PostgreSQL в общем
  кластере CNPG `shared` (namespace `databases`, эндпоинт
  `shared-rw.databases.svc.cluster.local:5432`). Роль `grafana`, база `grafana`
  и NetworkPolicy объявлены в `platform/cnpg/`; пароль приходит в под из
  Secret'а `grafana-db` (ключ `GRAFANA_DB_PASSWORD`).
- Локальный диск под `/var/lib/grafana` — `emptyDir`: это только скретч (кэш
  плагинов, индекс поиска), сами данные в Postgres, поэтому том не нужен.
- Логин администратора — `admin`, пароль — в кластерном Secret `grafana`
  (`GRAFANA_ADMIN_PASSWORD`), создаётся из SealedSecret
  `apps/grafana/k8s/sealedsecret.yaml`. Регистрация новых пользователей
  отключена; доступ к UI контролирует `oauth2-proxy`, локальный вход нужен для
  правок datasource и диагностики.
- Пароли `GRAFANA_ADMIN_PASSWORD` и `GRAFANA_DB_PASSWORD` продублированы в
  расшифровываемом реестре `apps/grafana/secrets.enc.env` (SOPS поверх age;
  приватный ключ — только на сервере). SealedSecret необратим, поэтому исходные
  значения достаются из этого файла.

## Провижининг

Datasource VictoriaMetrics описан декларативно в `config/datasources.yaml`
(uid `victoriametrics` зафиксирован — на него ссылаются панели дашбордов).

Дашборды тоже код: JSON-файлы в `config/dashboards/`, провайдер — в
`config/dashboards.yaml`. Провайдер собирается с `allowUiUpdates: false`:
источник правды — git, правки в UI не сохраняются. Оба файла и сами дашборды
монтируются в под через `configMapGenerator` (см. `kustomization.yaml`), поэтому
правка конфига сама запускает rollout.

JSON-файлы хранятся в читаемом виде (`indent=2`), суммарно 337946 Б. Это больше
лимита аннотации `kubectl.kubernetes.io/last-applied-configuration` (262144 Б),
с которым падает client-side apply, поэтому **Grafana применяется только
server-side apply** — он эту аннотацию не пишет:

```sh
kubectl apply --server-side --field-manager=homelab -k apps/grafana/
```

Остальные приложения репозитория пока применяются client-side; переход на
server-side для них — отдельная задача, не смешивать её с правками Grafana.
Причина миграции именно в размере: client-side apply падает на лимите аннотации
(проверено на стенде — `metadata.annotations: Too long` при 337946 Б). Побочный
плюс server-side — владение полями в `metadata.managedFields`, но на повреждённый
ConfigMap это не влияет, и отдельного подтверждения не требует.

Дашборды: `cloudnative-pg.json` и `postgresql-database.json` — экспорт из UI
Grafana; `traefik.json` — написан руками под метрики Traefik; `traefik-official.json`
— официальный дашборд Traefik с grafana.com, вендорен в репозиторий.

`traefik.json` и `traefik-official.json` не дублируют друг друга: официальный
не содержит ни одного запроса `traefik_router_*` (все 14 панелей смотрят на
service/entrypoint), per-router панели есть только в самописном. Per-router
метрики появляются при `metrics.prometheus.addRoutersLabels=true` в
`argocd/applications/traefik.yaml` (#284). Datasource везде указан как
`uid: victoriametrics`.

### Вендоренные дашборды с grafana.com

Grafana не умеет импортировать дашборд с grafana.com по ID в рантайме —
провижининг читает только файлы, git или HTTP. Поэтому community-дашборд
скачивается один раз и коммитится, а обновляется вручную.

| Файл | grafana.com ID | Ревизия | revisionId | Дата |
|---|---|---|---|---|
| `traefik-official.json` | 17346 | 9 | 33826 | 2026-09-26 |

При обновлении: скачать JSON, сверить с `uid: victoriametrics` (в исходнике
`${DS_PROMETHEUS}`), удалить ставшую ненужной переменную `DS_PROMETHEUS` типа
`datasource`, записать новую ревизию в таблицу выше. Скрипта автоматизации нет
сознательно — обновление редкое, а лишняя автоматизация вендоринга приводит к
тихим правкам дашборда.

База при переезде с SQLite не переносилась: дашборды экспортированы из старой
базы в JSON, единственный пользователь `admin` создаётся заново, алертов и
аннотаций не было.

## Развёртывание в Kubernetes

Разворачивается kustomize-набором:

```sh
kubectl apply -k apps/grafana/
```

`k8s/grafana.deployment.yaml` — Deployment (uid/gid 1000, probes, ресурсы,
`GF_DATABASE_*`), `k8s/grafana.service.yaml` — ClusterIP (порт 80 → 3000, Gatus и
Traefik ходят по `http://grafana/`), маршрут —
`platform/homelab/templates/routes/grafana.yaml` (`Host(grafana…)` за
`oauth2-proxy` + `secure-headers` + `ratelimit-default`).

## Проверка

```sh
curl --resolve grafana.${DOMAIN}:443:<node1-ip> \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://grafana.${DOMAIN}/
```

Ожидаемый ответ: `302` (redirect на oauth2-proxy). Health API напрямую:

```sh
kubectl exec deploy/grafana -- curl -fsS http://127.0.0.1:3000/api/health
```

Что Grafana подключена к Postgres, видно по логу старта (`database: postgres`)
и по отсутствию `grafana.db` в поде.
