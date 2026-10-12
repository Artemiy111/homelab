# node-exporter

Стандартный Prometheus-экспортер метрик хоста: отдаёт `node_*` (CPU, память, ФС,
сеть, load, pressure и т.д.) в формате exposition. Работает как DaemonSet — один
под на ноду, читает host-каталоги `/proc`, `/sys`, `/` через маунты
`/host/...`; hostNetwork не используется, порт наружу не публикуется.

Дублирует часть того, что уже собирает netdata, но `node_*` — это то, на что
написаны готовые Grafana-дашборды и Prometheus-правила.

Скрейпится vmagent'ом (job `node-exporter` в
`clusters/casa/apps/victoria-metrics/manifests/config/vmagent/scrape.yml`).

Проверка — в `RUNBOOK.md`.
