# VictoriaMetrics stack

Долгосрочное хранение метрик в дополнение к Netdata: Netdata остаётся
сборщиком посекундных метрик хоста и контейнеров, VictoriaMetrics хранит
историю всех сигналов. Дашборды строит Grafana — это отдельный сервис,
см. `apps/casa/grafana/`.

VM и vmagent наружу не публикуются: их UI нужен только для отладки, запросы
идут через Grafana. VMUI доступен по адресу `https://vm.example.com/` за
`oauth2-proxy`.

## Поток метрик

```
приложения /metrics ─┐
victoriametrics ─────┼──(scrape)──> vmagent ──(remote write)──> victoriametrics <── grafana
vmagent ─────────────┘
```

vmagent забирает `/metrics` приложений **напрямую** — оригинальные имена и
лейблы, без netdata-префиксов, поэтому работают готовые дашборды Grafana.
Netdata скрейпится только за метриками хоста и контейнеров.

Скрейп-конфиг трекается в Git: `config/vmagent/scrape.yml` и **секретов не
содержит**. Значения кредов подставляются vmagent из окружения по ссылкам
`%{VAR}` (env-подстановка в `-promscrape.config`); окружение приходит из k8s
Secrets и ConfigMap.

Цели: `victoriametrics`, `vmagent`, `traefik`, `authentik`,
`gatus`, `synapse`, `immich`, `livekit`, `tempo`, `athens`, `glitchtip`, `zot`,
`talk-hpb`, `longhorn`, `trivy-operator` (без аутентификации);
`uptime-kuma`, `navidrome`, `dawarich`, `forgejo`, `technitium`, `stalwart`
(креды из Secrets).

cert-manager скрейпится отдельными job'ами (`cert-manager`,
`cert-manager-webhook`, `cert-manager-cainjector`) по Service'ам.
Чарт cert-manager развешивает аннотации `prometheus.io/scrape` на своих подах,
но job с pod-discovery по аннотациям в конфиге нет, поэтому цели заданы явно.

## Хранение

Постоянные данные — `/storage/apps/victoria-metrics/vmdata`. Retention и порог
свободного места на томе заданы аргументами Deployment, размер тома — в PVC.
Значения здесь не дублируются: источник правды — манифесты.

### Ёмкость и retention

Retention, порог свободного места и размер тома выбираются вместе, и расчёт их
согласованности лежит в манифестах, а не здесь.

Независимый от этих значений риск: темп роста метрик меняется, и однажды данные
перестанут помещаться в том — storage перестаёт принимать запись, новые метрики
теряются, уже записанные данные целы. За местом на томах кластера следят алерты
группы `storage` в Grafana; что делать при срабатывании — в `RUNBOOK.md`.

## Креды целей

`VaultStaticSecret` в неймспейсе `monitoring`, по одному на путь
`kv/<владелец>/@monitoring/<кред>`. Владельцы: `uptime-kuma`, `dawarich`,
`forgejo`, `technitium`, `mailserver`, `local-ai`, `home-assistant`,
`navidrome`. Креды не хранятся в Secret `vmagent` скопом — каждый в
своём, и под каждый отдельная строка в политике `app/vmagent`.

## Алёрты

Правила живут в Grafana (группа `victoria-metrics`), доставляются в ntfy.
Пороги и обоснование — в `apps/casa/grafana/README.md`, раздел
«Алёрты». Реакция на сработавший алерт — в `RUNBOOK.md`.
