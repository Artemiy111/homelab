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
(после #468).

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

rustfs, seafile, open-webui, glitchtip, wud, docker-socket-proxy,
kube-state-metrics, migrate.

## Включение структурного вывода

| Сервис | Механизм | Статус |
|---|---|---|
| Immich | `IMMICH_LOG_FORMAT=json` | включено (#462) |
| Verdaccio | `log.format: json` | включено (#464) |
| WUD | `WUD_LOG_FORMAT=json` | включено (#464) |
| RustFS | `RUSTFS_OBS_LOG_STDOUT_ENABLED=true` | включено (#468): stdout-mirror в JSON, OTLP-экспорт логов выключен во избежание дубля |
| Stirling PDF | `logging.structured.format.console` | проверено на стенде: без эффекта (кастомный logback), остаётся текст |
| Vault | `log_format = "json"` | отложено: рестарт требует повторного unseal |

## Без штатного структурного вывода

Forgejo (только console/file/conn), oauth2-proxy (шаблоны строк), Nextcloud
(нет JSON-форматтера), Home Assistant, Jellyfin (нужен ручной Serilog
`logging.json`), Uptime Kuma, Seafile, Technitium, 3x-ui, Jitsi (prosody/jicofo/
jvb), coturn, Element-web, redis/valkey, mariadb, ATS. Для них либо оставляем
текст, либо парсим regex-стадиями в Alloy.
