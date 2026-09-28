# Форматы логов приложений homelab

Дата: 2026-09-28. Инвентарь фактического вывода логов: какой контейнер отдаёт
структуру (JSON или logfmt), а какой — чистый текст. Дополняет
[observability-standards-and-approaches.md](observability-standards-and-approaches.md)
§3.1 (logfmt и JSON — оба структурированы) и issue #461.

## Как получено

Источник — Loki API `detected_fields`: возвращает имена и типы полей, которые
Loki распознал в строках, и **не отдаёт содержимое логов**. Окно — 24 часа.
Пустой ответ означает, что строк за окно не было (тихий контейнер), а не
отсутствие структуры.

```sh
kubectl -n monitoring exec deploy/grafana -- curl -sG \
  http://loki:3100/loki/api/v1/detected_fields \
  --data-urlencode 'query={container="<name>"}' \
  --data-urlencode "start=<unix_ns>" --data-urlencode "end=<unix_ns>"
```

## JSON

traefik (access), authentik, zot, headlamp, infisical, postgres (CNPG отдаёт
JSON по умолчанию), cert-controller, manager, worker, zitadel-login, rustfs
(после #468), open-webui (после #498).

## logfmt

grafana, loki, tempo, alloy, vmagent, victoriametrics, node-exporter,
mysqld-exporter, netdata, gatus, Argo CD (application-controller,
applicationset-controller, repo-server, server), calico-node,
konnectivity-agent, longhorn-manager, longhorn-csi-plugin, instance-manager,
csi-attacher, csi-provisioner, jicofo, jvb, navidrome, athens, synapse, vault,
sure, sure-worker, runner, talk-hpb, beszel-agent, cert-manager-cainjector,
zitadel, dind, radar.

## Чистый текст

nextcloud, jellyfin, paperless, stirlingpdf, home-assistant, forgejo,
uptime-kuma, dawarich, 3x-ui, element-web, matrix-rtc-auth, oauth2-proxy,
mariadb, redis, valkey, prosody, sidekiq, web, glitchtip-worker, mail, cron.
(immich-server и verdaccio из этого списка уже переведены на JSON, см. #461.)

## Нет данных в окне

seafile, glitchtip, wud, docker-socket-proxy,
kube-state-metrics, migrate.

## Включение структурного вывода

| Сервис | Механизм | Статус |
|---|---|---|
| Immich | `IMMICH_LOG_FORMAT=json` | включено (#462) |
| Verdaccio | `log.format: json` | включено (#464) |
| WUD | `WUD_LOG_FORMAT=json` | включено (#464) |
| RustFS | `RUSTFS_OBS_LOG_STDOUT_ENABLED=true` | включено (#468): stdout-mirror в JSON, OTLP-экспорт логов выключен во избежание дубля |
| Open WebUI | `LOG_FORMAT=json` | включено (#498): однострочный JSON, trace_id/span_id в `extra` |
| Stirling PDF | `logging.structured.format.console` | проверено на стенде: без эффекта (кастомный logback), остаётся текст |
| Vault | `log_format = "json"` | отложено: рестарт требует повторного unseal |

## Без штатного структурного вывода

Forgejo (только console/file/conn), oauth2-proxy (шаблоны строк), Nextcloud
(нет JSON-форматтера), Home Assistant, Jellyfin (нужен ручной Serilog
`logging.json`), Uptime Kuma, Seafile, Technitium, 3x-ui, Jitsi (prosody/jicofo/
jvb), coturn, Element-web, redis/valkey, mariadb, ATS. Для них либо оставляем
текст, либо парсим regex-стадиями в Alloy.

Отдельно — **Calico** (`calico-kube-controllers`, `calico-node`): logrus с
кастомным форматтером (`libcalico-go/logutils`) плюс klog для warning'ов
client-go. JSON нативно не отдаёт; настраивается только уровень (`LOG_LEVEL`
или `KubeControllersConfiguration.spec.logSeverityScreen`). Структуру может дать
только парсер на шиппере (Alloy).

Прочее без штатного JSON:

- **konnectivity-agent**: klog, флаг `--logging-format` не поддерживает (и
  управляется k0s). Alloy вытаскивает уровень из первой буквы строки в
  `klog_level`.
- **glitchtip-worker**: Celery, воркер создаётся кодом без формата — JSON нет.
- **dawarich**: Rails/Sidekiq — штатного JSON нет.
- **Synapse**: JSON умеет (`log_config` + `synapse.logging.TerseJsonFormatter`),
  но конфиг задаётся в `homeserver.yaml` на хосте (вне Git) — см. #482.
