# VictoriaMetrics stack

Долгосрочное хранение метрик в дополнение к Netdata: Netdata остаётся
сборщиком посекундных метрик хоста и контейнеров, VictoriaMetrics хранит
историю всех сигналов. Дашборды строит Grafana — это отдельный сервис,
см. `apps/grafana/`.

Сервисы развёрнуты kustomize-набором `apps/victoria-metrics/`.

Состав:

| Deployment | Роль | Порт |
|---|---|---|
| `victoriametrics` | TSDB single-node (`victoria-metrics:v1.150.0`) | 8428, ClusterIP |
| `vmagent` | скрейпит приложения, netdata и self, пишет в VM (`vmagent:v1.150.0`) | 8429, ClusterIP |

VM и vmagent наружу не публикуются: их UI нужен только для отладки, запросы
идут через Grafana. VMUI доступен по адресу `https://vm.example.com/` за
`oauth2-proxy` (см. `platform/homelab/templates/routes/victoria-metrics.yaml`).

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

## Алёрты

Правила живут в Grafana (`apps/grafana/config/alerting/victoria-metrics.yaml`),
доставляются в ntfy. Пороги и обоснование — в `apps/grafana/README.md`,
раздел «Алёрты». Ниже — что делать, когда алерт уже сработал.

### `vm-free-disk-space-low` / `vm-storage-filling-fast`

Свободного места меньше 1.5 ГБ, либо прогноз обнуления меньше чем за 3 суток.
Это предупреждение, а не авария: TSDB ещё пишет.

```sh
kubectl exec deploy/victoriametrics -n monitoring -- wget -qO- \
  'http://127.0.0.1:8428/api/v1/query?query=vm_data_size_bytes'
kubectl get pvc victoriametrics-vmdata -n monitoring
```

Смотреть `vm_data_size_bytes` по `type`: `storage/big` — основной объём,
`storage/small` — ещё не слитый буфер, `indexdb/*` — индексы. Расширение PVC
на месте (Longhorn сохраняет UID и данные):

```sh
kubectl patch pvc victoriametrics-vmdata -n monitoring -p \
  '{"spec":{"resources":{"requests":{"storage":"16Gi"}}}}'
```

Если расширять некуда, снижать retention (§ «ёмкость не соответствует
retention»): после смены `-retentionPeriod` нужен `kubectl rollout restart
deploy/victoriametrics`, и данные переживут перезапуск, но временный ряд
станет короче.

### `vm-pending-rows-backlog`

Очередь несохранённых строк выше 1 млн дольше 30 минут. Обычно предшествует
`vm-storage-read-only`: сброс на диск сначала замедляется, потом падает.

```sh
kubectl exec deploy/victoriametrics -n monitoring -- wget -qO- \
  'http://127.0.0.1:8428/api/v1/query?query=vm_pending_rows'
```

Смотреть, растёт ли `type="storage"` монотонно. Если да — места на диске уже
нет, и это ложное «медленно»; лечится расширением PVC.

### `vm-storage-read-only`

Авария: vmagent получает 503 на remote write, новые метрики теряются, уже
записанные данные целы. Подробный разбор — `docs/incidents/
0003-victoriametrics-pvc-read-only.md`.

```sh
kubectl exec deploy/victoriametrics -n monitoring -- wget -qO- \
  'http://127.0.0.1:8428/api/v1/query?query=vm_free_disk_space_bytes'
```

Порядок действий: расширить PVC, дождаться `vm_storage_is_read_only == 0`,
и только после этого `kubectl rollout restart deploy/victoriametrics`.
Рестарт до расширения не поможет — TSDB снова упрётся в тот же предел.

### `scrape-target-down`

Таргет отвечает, но метрики с него не читаются: 401/403 на `/metrics`, битый
токен, сломанный exporter. Значение `job` в алерте — имя таргета из
`config/vmagent/scrape.yml`.

```sh
kubectl exec deploy/victoriametrics -n monitoring -- wget -qO- \
  'http://127.0.0.1:8428/api/v1/query?query=up'
```

Если падает сразу много таргетов, ищите общую причину, а не каждый таргот по
отдельности: один и тот же образ экспортера, одна сетевая политика, один
утёкший токен. Разовые обрывы лечатся увеличением `for` у правила, а не
ослаблением селектора.

## Развёртывание в Kubernetes

kustomize-набор в `apps/victoria-metrics/`: манифесты в `k8s/`, а скрейп-конфиг
`config/vmagent/scrape.yml` собирается в ConfigMap `vmagent-scrape` через
`configMapGenerator`. Kustomize добавляет к имени ConfigMap хэш содержимого и
переписывает ссылку в `vmagent.deployment.yaml`, поэтому правка `scrape.yml`
сама меняет pod-template и запускает rollout — отдельный
`kubectl rollout restart` не нужен (vmagent не перечитывает файл на ходу).

- `victoriametrics.deployment.yaml`, `victoriametrics.service.yaml` — TSDB;
- `vmagent.deployment.yaml`, `vmagent.service.yaml` — сборщик; монтирует
  собранный из `config/vmagent/scrape.yml` ConfigMap и получает креды целей из
  Secrets;
- `vmagent-rbac.yaml` — доступ к kubelet/cAdvisor и service discovery;
- `vmdata.pvc.yaml` — том TSDB;
- `sealedsecret.yaml` — Secret `vmagent` (`UPTIME_KUMA_METRICS_API_KEY`); прочие
  креды берутся из Secrets соответствующих сервисов (`navidrome`, `dawarich`,
  `forgejo`, `technitium`, `mailserver`).

Применение (от `artlab` на сервере, после `git pull --ff-only`):

```sh
kubectl apply -k apps/victoria-metrics/
```

## Проверка

Наличие целей и их состояние:

```sh
kubectl exec deploy/victoriametrics -- wget -qO- \
  'http://127.0.0.1:8428/api/v1/query?query=up' | grep -o '"job":"[^"]*"'
```

HTTP-маршрут VMUI (ожидаем 302 на oauth2-proxy):

```sh
curl --resolve vm.${DOMAIN}:443:<node1-ip> \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://vm.${DOMAIN}/
```
