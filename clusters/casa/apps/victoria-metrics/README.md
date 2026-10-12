# VictoriaMetrics stack

Долгосрочное хранение метрик в дополнение к Netdata: Netdata остаётся
сборщиком посекундных метрик хоста и контейнеров, VictoriaMetrics хранит
историю всех сигналов. Дашборды строит Grafana — это отдельный сервис,
см. `clusters/casa/apps/grafana/`.

VM и vmagent наружу не публикуются: их UI нужен только для отладки, запросы
идут через Grafana. VMUI доступен по адресу `https://vm.example.com/` за
`oauth2-proxy`.

## Поток метрик

```
приложения /metrics ─┐
                ┌──(scrape)──> vmagent ──(remote write)──> victoriametrics <── grafana
victoriametrics ─────┤
vmagent ─────────────┘
```

vmagent забирает `/metrics` приложений **напрямую** — оригинальные имена и
лейблы, без netdata-префиксов, поэтому работают готовые дашборды Grafana.
Netdata скрейпится только за метриками хоста и контейнеров.

Скрейп-конфиг трекается в Git: `config/vmagent/scrape.yml` и **секретов не
содержит**. Значения кредов подставляются vmagent из окружения по ссылкам
`%{VAR}` (env-подстановка в `-promscrape.config`); окружение приходит из k8s
Secrets и ConfigMap.

Цели: `victoriametrics`, `vmagent`, `traefik`, `authentik`, `wud`,
`gatus`, `synapse`, `immich`, `livekit`, `tempo`, `athens`, `glitchtip`, `zot`,
`prosody`, `talk-hpb`, `longhorn` (без аутентификации); `uptime-kuma`,
`navidrome`, `dawarich`, `forgejo`, `technitium`, `stalwart`, `seafile` (креды из
Secrets).

cert-manager скрейпится тремя отдельными job'ами (`cert-manager`,
`cert-manager-webhook`, `cert-manager-cainjector`) по Service'ам на порту 9402.
Чарт cert-manager развешивает аннотации `prometheus.io/scrape` на своих подах,
но job с pod-discovery по аннотациям в конфиге нет, поэтому цели заданы явно.

## Хранение

Постоянные данные — `/storage/apps/victoria-metrics/vmdata`, retention
задан аргументом Deployment (`-retentionPeriod=180d`).

### ёмкость не соответствует retention

При темпе роста ≈200 МБ/сутки (замерено 2026-09-26) retention в 180 суток
требует ≈36 ГБ, а PVC `victoriametrics-vmdata` — 8 Ги. То есть 180 суток
данные не проживут: диск заполнится примерно через 20 суток от нуля, задолго
до того, как retention что-либо удалит. Значение `-retentionPeriod=180d` на
текущей ёмкости — декларация, а не рабочее ограничение.

Два честных варианта, и выбор между ними не сводится к «увеличить диск»:

1. **Диск догоняет retention.** Расширить PVC до ~48 Ги (36 ГБ данных + запас
   на merge backlog и минимум свободного места) и принять, что homelab
   держит 180 суток истории.
2. **Retention догоняет диск.** Снизить `-retentionPeriod` до недель, которые
   реально помещаются, и не платить за хранение данных, которые всё равно
   никто не смотрит.

Первый вариант упирается в ёмкость узла, второй — в полезность истории. Это
решение владельца, а не следствие этого README; до него алерты ниже должны
работать.

## Креды целей

Девять `VaultStaticSecret` в неймспейсе `monitoring`, по одному на путь
`kv/<владелец>/@monitoring/<кред>`. Владельцы: `uptime-kuma`, `dawarich`,
`forgejo`, `technitium`, `mailserver`, `local-ai`, `home-assistant`,
`navidrome`, `seafile`. Креды не хранятся в Secret `vmagent` скопом — каждый в
своём, и под каждый отдельная строка в политике `app/vmagent`.

## Алёрты

Правила живут в Grafana (группа `victoria-metrics`), доставляются в ntfy.
Пороги и обоснование — в `clusters/casa/apps/grafana/README.md`, раздел
«Алёрты». Реакция на сработавший алерт — в `RUNBOOK.md`.
