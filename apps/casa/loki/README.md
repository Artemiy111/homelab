# Loki

Хранилище логов. Принимает push по Loki HTTP API от Grafana Alloy
(`apps/casa/alloy/`) и отдаёт логи Grafana как datasource. Развёрнут в namespace
`monitoring`; наружу не публикуется — доступ только через Grafana.

Модель — монолит в одном поде (`grafana/loki`), хранение на локальном диске
(файловая система), индексируются только лейблы, содержимое строк сжато.

```
Alloy (DaemonSet) ──push──> loki:3100 <── Grafana (Explore)
```

## Хранилище

Конфиг: `auth_enabled: false`, схема `tsdb`/`v13`, filesystem-хранилище,
retention задан в конфиге и удаляет старые данные через compactor. Данные лежат
на PVC `loki-data` (Longhorn, `longhorn-retain`); размер тома — в манифесте PVC
и расширяется на месте, порядок — в `RUNBOOK.md`.

Проверка — в `RUNBOOK.md`.
