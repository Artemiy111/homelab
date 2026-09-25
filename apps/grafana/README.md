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

JSON-файлы хранятся в minified-виде (одна строка): так суммарный ConfigMap
укладывается в лимит аннотации `kubectl.kubernetes.io/last-applied-configuration`
(262144 Б), с которым падает client-side apply. Это экспорт из Grafana, а не
рукописный файл; при добавлении дашбордов следите за суммарным размером.

База при переезде с SQLite не переносилась: дашборды экспортированы из старой
базы в JSON, единственный пользователь `admin` создаётся заново, алертов и
аннотаций не было.

## Развёртывание в Kubernetes

Разворачивается kustomize-набором:

```sh
kubectl apply --server-side --field-manager=homelab -k apps/grafana/
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
