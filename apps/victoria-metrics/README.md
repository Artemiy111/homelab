# VictoriaMetrics stack

Долгосрочное хранение метрик в дополнение к Netdata: Netdata остаётся
сборщиком посекундных метрик хоста и контейнеров, VictoriaMetrics хранит
историю всех сигналов. Дашборды строит Grafana — это отдельный сервис,
см. `apps/grafana/`.

Сервисы развёрнуты в Kubernetes (`apps/victoria-metrics/k8s/`).

Состав:

| Deployment | Роль | Порт |
|---|---|---|
| `victoriametrics` | TSDB single-node (`victoria-metrics:v1.150.0`) | 8428, ClusterIP |
| `vmagent` | скрейпит приложения, netdata и self, пишет в VM (`vmagent:v1.150.0`) | 8429, ClusterIP |

VM и vmagent наружу не публикуются: их UI нужен только для отладки, запросы
идут через Grafana. VMUI доступен по адресу `https://vm.example.com/` за
`oauth2-proxy` (см. `apps/victoria-metrics/route.yaml`).

## Поток метрик

```
приложения /metrics ─┐
netdata:19999 ───────┼──(scrape)──> vmagent ──(remote write)──> victoriametrics <── grafana
victoriametrics ─────┤
vmagent ─────────────┘
```

vmagent забирает `/metrics` приложений **напрямую** — оригинальные имена и
лейблы, без netdata-префиксов, поэтому работают готовые дашборды Grafana.
Netdata скрейпится только за метриками хоста и контейнеров.

Скрейп-конфиг трекается в Git: `config/vmagent/scrape.yml` и **секретов не
содержит**. Значения кредов подставляются vmagent из окружения по ссылкам
`%{VAR}` (env-подстановка в `-promscrape.config`); окружение приходит из k8s
Secrets и ConfigMap (см. `apps/victoria-metrics/k8s/vmagent.deployment.yaml`).

Цели: `netdata`, `victoriametrics`, `vmagent`, `traefik`, `authentik`, `wud`,
`gatus`, `synapse`, `immich`, `livekit` (без аутентификации); `uptime-kuma`,
`navidrome`, `dawarich`, `forgejo`, `technitium`, `stalwart` (креды из Secrets).

## Хранение

Постоянные данные — `/storage/apps/victoria-metrics/vmdata`, retention
задан аргументом Deployment (`-retentionPeriod=180d`).

## Развёртывание в Kubernetes

Манифесты в `apps/victoria-metrics/k8s/`:

- `victoriametrics.deployment.yaml`, `victoriametrics.service.yaml` — TSDB;
- `vmagent.deployment.yaml`, `vmagent.service.yaml` — сборщик; монтирует
  `config/vmagent/scrape.yml` (hostPath) и получает креды целей из Secrets;
- `sealedsecret.yaml` — Secret `vmagent` (`UPTIME_KUMA_METRICS_API_KEY`); прочие
  креды берутся из Secrets соответствующих сервисов (`navidrome`, `dawarich`,
  `forgejo`, `technitium`, `mailserver`).

Применение (от `artlab` на сервере, после `git pull --ff-only`):

```sh
kubectl apply -f apps/victoria-metrics/k8s/
kubectl rollout restart deploy/vmagent   # после правки scrape.yml
```

## Проверка

Наличие целей и их состояние:

```sh
kubectl exec deploy/victoriametrics -- wget -qO- \
  'http://127.0.0.1:8428/api/v1/query?query=up' | grep -o '"job":"[^"]*"'
```

HTTP-маршрут VMUI (ожидаем 302 на oauth2-proxy):

```sh
curl --resolve vm.${DOMAIN}:443:192.0.2.10 \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://vm.${DOMAIN}/
```
