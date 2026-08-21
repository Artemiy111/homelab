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
`docs/research/monitoring-systems-overview.md` (§7): приложения, которые уже
отдают `/metrics` без дополнительных настроек:

- Authentik: `http://authentik-server:9300/metrics`;
- WUD: `http://wud:3000/metrics`.

Новые цели добавляются в этот файл и применяются перезапуском контейнера:

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
bash ./init.sh
docker compose up -d
```

Проверка после запуска:

```sh
docker compose ps
curl -fsS http://netdata:19999/v1/info | head -c 200; echo
```

Netdata Cloud не используется: SSO у локального агента возможно только через
облако, поэтому доступ к UI контролирует Traefik + oauth2-proxy.
