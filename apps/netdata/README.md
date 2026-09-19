# Netdata

Netdata собирает посекундные метрики хоста и Docker-контейнеров, отдаёт
встроенный UI и Prometheus-эндпоинт. UI доступен через Traefik по адресу
`https://netdata.example.com/` и закрыт forward auth (oauth2-proxy), потому
что локальный агент Netdata собственной аутентификации не имеет. Порт 19999 на
хосте не публикуется.

Постоянные данные (`config`, `lib`, `cache`) хранятся в томе состояния
сервиса. Контейнеру подключены `/proc`, `/sys`, `/var/log` и Docker socket
только для чтения — метрик и имён контейнеров.

`no-new-privileges` не используется: плагин `apps.plugin` в официальном образе —
setuid-binary, и запрет новых привилегий ломает сбор метрик процессов.
Дополнительно выданы capabilities `SYS_PTRACE` и `DAC_READ_SEARCH` (чтение
`/proc` и journal-файлов хоста).

## Метрики приложений

Netdata не собирает метрики приложений: их забирает **vmagent** напрямую из
`/metrics` каждого сервиса и пишет в VictoriaMetrics (оригинальные имена и
лейблы, без netdata-префиксов). Netdata отвечает только за хост и контейнеры.
Цели и их аутентификация описаны в `apps/victoria-metrics/k8s/vmagent.configmap.yaml`.

Наружу Netdata отдаёт только собственный Prometheus-эндпоинт — его скрейпит
vmagent (job `netdata`):

```sh
curl -fsS 'http://netdata:19999/api/v1/allmetrics?format=prometheus'
```

## Первый запуск

Разворачивается манифестами в apps/netdata/k8s/.

Проверка после запуска:

```sh
curl -fsS 'http://netdata:19999/api/v1/info' | head -c 200; echo
```

Netdata Cloud не используется: SSO у локального агента возможно только через
облако, поэтому доступ к UI контролирует Traefik + oauth2-proxy.
