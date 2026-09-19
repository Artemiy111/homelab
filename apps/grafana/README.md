# Grafana

Grafana — единый UI для дашбордов поверх VictoriaMetrics. Сервис развёрнут в
Kubernetes (`apps/grafana/k8s/`) и доступен через Traefik кластера по адресу
`https://grafana.example.com/` за `oauth2-proxy`.

Отделён от `apps/victoria-metrics/`: Grafana — независимый слой визуализации
(свои образ, данные, секрет и маршрут), который лишь читает метрики из
VictoriaMetrics как datasource.

## Данные и доступ

- Образ `grafana/grafana:13.2.0` (зафиксирован по digest), uid/gid `1000`
  (совпадает с владельцем каталога на хосте), `Recreate` из-за hostPath.
- Постоянные данные — `/storage/apps/grafana` (SQLite-база, дашборды,
  пользователи), монтируется в `/var/lib/grafana`.
- Логин администратора — `admin`, пароль — в кластерном Secret `grafana`
  (`GRAFANA_ADMIN_PASSWORD`), создаётся из SealedSecret
  `apps/grafana/k8s/sealedsecret.yaml`. Регистрация новых пользователей отключена; доступ к
  UI контролирует `oauth2-proxy`, локальный вход нужен для правок дашбордов и
  datasource.

## Провижининг datasource

Datasource VictoriaMetrics описан декларативно в ConfigMap
`grafana-provisioning` (`apps/grafana/k8s/grafana-provisioning.configmap.yaml`) и
монтируется в `/etc/grafana/provisioning/datasources`. URL —
`http://victoriametrics:8428` (ClusterIP-сервис из `apps/victoria-metrics/`).

## Развёртывание в Kubernetes

Манифесты в `apps/grafana/k8s/`:

- `grafana.deployment.yaml` — Deployment (uid/gid 1000, probes, ресурсы,
  hostPath-данные `/storage/apps/grafana`, provisioning из ConfigMap);
- `grafana.service.yaml` — ClusterIP, порт 80 → 3000 (Gatus и Traefik ходят по
  `http://grafana/`);
- `platform/traefik/grafana.ingressroute.yaml` — `Host(grafana…)` за `oauth2-proxy` +
  `secure-headers` + `ratelimit-default`.

Применение (от `artlab` на сервере, после `git pull --ff-only`):

```sh
kubectl apply -f apps/grafana/k8s/
```

## Проверка

```sh
curl --resolve grafana.${DOMAIN}:443:192.0.2.10 \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://grafana.${DOMAIN}/
```

Ожидаемый ответ: `302` (redirect на oauth2-proxy). Health API напрямую:

```sh
kubectl exec deploy/grafana -- curl -fsS http://127.0.0.1:3000/api/health
```
