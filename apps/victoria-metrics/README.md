# VictoriaMetrics stack

Долгосрочное хранение метрик в дополнение к Netdata: Netdata остаётся
сборщиком посекундных метрик и UI «здесь и сейчас», VictoriaMetrics хранит
историю. Дашборды строит Grafana — это отдельный сервис, см. `apps/grafana/`.

Состав:

| Контейнер | Роль | Порт |
|---|---|---|
| `victoriametrics` | TSDB single-node (`victoria-metrics:v1.150.0`) | 8428, только внутри `traefiknet` |
| `vmagent` | скрейпит netdata и self-метрики, пишет в VM (`vmagent:v1.150.0`) | 8429, только внутри `traefiknet` |

VM и vmagent наружу не публикуются: их UI нужен только для отладки, запросы
идут через Grafana. DNS-запись не требуется — wildcard `*.${DOMAIN}` уже
указывает на сервер (см. `technitium/README.md`).

## Поток метрик

```
netdata:19999 ──(prometheus scrape)──> vmagent ──(remote write)──> victoriametrics
```

vmagent забирает `/api/v1/allmetrics?format=prometheus` у netdata — вместе с
хостом и Docker это автоматически включает все цели из
`netdata/config/go.d/prometheus.conf` (traefik, forgejo, immich и т.д.).
Скрейп-конфиг трекается в Git: `config/vmagent/scrape.yml`, секретов не
содержит — все цели отдают метрики внутри `traefiknet`.

Datasource Grafana (VictoriaMetrics) настраивается в самом сервисе Grafana:
см. `apps/grafana/`.

## Хранение

Постоянные данные — `$APPS_STORAGE_PATH/victoria-metrics/vmdata`. Retention
задаётся в `config.env` (`VM_RETENTION_PERIOD`, по умолчанию 180d).

## Первый запуск

```sh
bash scripts/bootstrap-platform.sh victoria-metrics
```

Или через bootstrap: каталог добавлен в `scripts/bootstrap-platform.sh`.

## Проверка после запуска

```sh
docker compose ps
curl -fsS 'http://localhost:8428/health'   # изнутри контейнера VM
curl -fsS 'http://localhost:8429/health'   # изнутри контейнера vmagent
```

Наличие серий netdata в VM:

```sh
docker exec vmagent wget -qO- 'http://victoriametrics:8428/api/v1/query?query=up{job="netdata"}'
```

## Обновление конфигурации

- Скрейп-цели: править `config/vmagent/scrape.yml`, затем
  `docker compose restart vmagent`.
- Retention: править `config.env`, затем `docker compose up -d victoriametrics`.
