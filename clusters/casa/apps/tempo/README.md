# Tempo

Хранилище трейсов. Принимает OTLP от `otel-collector` и отдаёт трейсы Grafana
как datasource. Развёрнут в namespace `monitoring` рядом с остальным стеком
наблюдаемости.

```
Traefik ──OTLP/HTTP:4318──> otel-collector ──OTLP/gRPC:4317──> tempo <── Grafana
```

Приложения отдают трейсы в `otel-collector` по OTLP; отдельный приёмник у Tempo
наружу не публикуется. Первый источник — Traefik: он шлёт OTLP на
`otel-collector:4318/v1/traces` (см. `clusters/casa/platform/traefik/app.yaml`), поэтому
трейс появляется от любого HTTP-запроса через ingress без правки приложений.

## Хранилище

Трейсы лежат на PVC `tempo-data` (Longhorn, `longhorn-retain`, 5 Ги) в
`/var/tempo`: `wal` — незакрытые блоки, `blocks` — скомпактированные. Retention
пока дефолтный (336 ч, 14 суток); настройка под локальный бэкенд в Tempo 3.0
живёт в `backend_scheduler.provider.compaction.compaction.block_retention` —
зададим её, если 14 суток окажется мало для объёма.

В production Tempo принято хранить трейсы в S3-совместимом объектном хранилище
(у homelab для этого есть RustFS): это позволяет переживать потерю узла и не
ограничиваться локальным диском. Переезд на S3 — отдельная задача.

Проверка — в `RUNBOOK.md`.
