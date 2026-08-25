# VictoriaMetrics stack

Долгосрочное хранение метрик в дополнение к Netdata: Netdata остаётся
сборщиком посекундных метрик и UI «здесь и сейчас», VictoriaMetrics хранит
историю, Grafana строит дашборды.

Состав:

| Контейнер | Роль | Порт |
|---|---|---|
| `victoriametrics` | TSDB single-node (`victoria-metrics:v1.150.0`) | 8428, только внутри `traefiknet` |
| `vmagent` | скрейпит netdata и self-метрики, пишет в VM (`vmagent:v1.150.0`) | 8429, только внутри `traefiknet` |
| `grafana` | дашборды (`grafana:13.2.0`) | 3000 через Traefik |

Grafana доступен по адресу `https://grafana.example.com/` за oauth2-proxy,
как остальные сервисы. VM и vmagent наружу не публикуются: их UI нужен только
для отладки, запросы идут через Grafana. DNS-запись не требуется — wildcard
`*.${DOMAIN}` уже указывает на сервер (см. `technitium/README.md`).

## Поток метрик

```
netdata:19999 ──(prometheus scrape)──> vmagent ──(remote write)──> victoriametrics <── grafana
```

vmagent забирает `/api/v1/allmetrics?format=prometheus` у netdata — вместе с
хостом и Docker это автоматически включает все цели из
`netdata/config/go.d/prometheus.conf` (traefik, forgejo, immich и т.д.).
Скрейп-конфиг трекается в Git: `config/vmagent/scrape.yml`, секретов не
содержит — все цели отдают метрики внутри `traefiknet`.

Datasource Grafana провижинится декларативно:
`config/grafana/provisioning/datasources/victoria-metrics.yaml`.

## Хранение

Постоянные данные — `$APPS_STORAGE_PATH/victoria-metrics`
(`vmdata`, `grafana`). Retention задаётся в `config.env`
(`VM_RETENTION_PERIOD`, по умолчанию 180d).

Grafana работает под `user: "1000:1000"` (uid artlab) — bind mount без chown.
Логин администратора — `admin`, пароль генерируется при первом запуске и
хранится в `secrets.enc.env` (`GRAFANA_ADMIN_PASSWORD`). Регистрация новых
пользователей отключена; доступ к UI контролирует oauth2-proxy, локальный вход
нужен для правок дашбордов и datasource.

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

HTTP-маршрут Grafana (ожидаем 302 на oauth2-proxy):

```sh
curl --resolve grafana.example.com:443:192.0.2.10 \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://grafana.example.com/
```

## Обновление конфигурации

- Скрейп-цели: править `config/vmagent/scrape.yml`, затем
  `docker compose restart vmagent`.
- Datasource: править provisioning-файл, затем `docker compose restart grafana`.
- Retention: править `config.env`, затем `docker compose up -d victoriametrics`.
