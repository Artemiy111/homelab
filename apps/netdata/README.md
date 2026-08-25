# Netdata

Netdata собирает посекундные метрики хоста, Docker-контейнеров и приложений,
отдаёт встроенный UI и Prometheus-эндпоинт. UI доступен через Traefik по адресу
`https://netdata.example.com/` и закрыт forward auth (oauth2-proxy), потому
что локальный агент Netdata собственной аутентификации не имеет. Порт 19999 на
хосте не публикуется.

Постоянные данные находятся в `$APPS_STORAGE_PATH/netdata`
(`config`, `lib`, `cache`). Контейнеру подключены `/proc`, `/sys`, `/var/log`
и Docker socket с флагом `ro` — только для чтения метрик и имён контейнеров.

`no-new-privileges` не используется: плагин `apps.plugin` в официальном образе —
setuid-binary, и запрет новых привилегий ломает сбор метрик процессов.
Дополнительно выданы capabilities `SYS_PTRACE` и `DAC_READ_SEARCH` (чтение
`/proc` и journal-файлов хоста).

## Метрики приложений

Сбор Prometheus-метрик приложений настроен декларативно в
`config/go.d/prometheus.conf`. Цели выбраны по аудиту
`docs/research/monitoring-systems-overview.md` (§7):

| Цель | Источник |
|---|---|
| `authentik-server:9300` | отдаёт метрики без настройки |
| `wud:3000/metrics` | отдаёт метрики без настройки |
| `traefik:8082/metrics` | entrypoint `metrics` в `traefik.tpl.yaml` |
| `gatus:8080/metrics` | `metrics: true` в `gatus/config/config.yaml` |
| `uptime-kuma:3001/metrics` | API-ключ из `uptime-kuma/.env` (`UPTIME_KUMA_METRICS_API_KEY`, создаётся в UI Kuma) |
| `navidrome:4533/metrics_<секрет>` | секретный путь из `navidrome/.env` |
| `dawarich:3000/metrics` (basic auth) | env в `dawarich/compose.yaml` |
| `forgejo:3000/metrics?token=…` | токен из `forgejo/.env` |
| `element-synapse:9009/_synapse/metrics` | listener в `homeserver.tpl.yaml` |
| `immich-server:8081/metrics` | `IMMICH_TELEMETRY_INCLUDE=all` в `.env` |
| `element-livekit:6789/metrics` | блок `prometheus:` в конфиге LiveKit |
| `technitium:5380/api/dashboard/metrics/text` | Bearer-токен из `technitium/.env` |
| `mailserver:8080/metrics/prometheus` | Basic auth; секрет — env `STALWART_METRICS_PASSWORD`, включается в WebUI Stalwart |

Креды целей с аутентификацией живут только в `.env` соответствующих сервисов;
`netdata/init.sh` читает их при рендере и запекает в файл
`$APPS_STORAGE_PATH/netdata/config/go.d/prometheus.conf` (go.d не подставляет
переменные окружения в конфиги, а готовый файл содержит секреты и хранится
только на сервере).

Не подключены (нужен ручной шаг или вскрывают метрики наружу): Vault
(маршрут без oauth, unauth-метрики были бы публичными), Technitium,
LocalAI, Home Assistant (long-lived токены через UI), Stalwart (конфиг
в административной БД), talk-hpb (сторонний модуль eturnal).

Новые цели добавляются в `config/go.d/prometheus.conf` и применяются
перезапуском контейнера:

```sh
docker compose restart netdata
```

Собранные серии видны в UI (раздел «Prometheus endpoints») и в
Prometheus-формате:

```sh
curl -fsS 'http://netdata:19999/api/v1/allmetrics?format=prometheus'
```

## Первый запуск

```sh
bash scripts/bootstrap-platform.sh netdata
```

Проверка после запуска:

```sh
docker compose ps
curl -fsS 'http://netdata:19999/api/v1/info' | head -c 200; echo
```

Netdata Cloud не используется: SSO у локального агента возможно только через
облако, поэтому доступ к UI контролирует Traefik + oauth2-proxy.
