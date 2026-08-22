# Сбор Prometheus-метрик приложений homelab.
# Цели выбраны по аудиту: docs/research/monitoring-systems-overview.md, §7.
# Переменные ${NETDATA_*} раскрываются go.d из окружения контейнера
# (проброс в compose.yaml, значения зеркалятся из .env сервисов в init.sh).
jobs:
  # Уже отдаёт /metrics без настройки.
  - name: authentik
    url: http://authentik-server:9300/metrics

  - name: wud
    url: http://wud:3000/metrics

  # Инфраструктура.
  - name: traefik
    url: http://traefik:8082/metrics

  - name: gatus
    url: http://gatus:8080/metrics

  # Приложения с включённым экспортом метрик (см. compose/init.sh каждого).
  - name: navidrome
    url: http://navidrome:4533/metrics_${NETDATA_NAVIDROME_METRICS_PATH}

  - name: dawarich
    # Приложение редиректит внутренние запросы на публичный HTTPS-URL.
    url: https://dawarich.example.com/metrics
    username: ${NETDATA_DAWARICH_METRICS_USERNAME}
    password: ${NETDATA_DAWARICH_METRICS_PASSWORD}

  - name: forgejo
    # Токен передаётся как Bearer (см. forgejo docs, [metrics] TOKEN).
    url: http://forgejo:3000/metrics
    headers:
      Authorization: "Bearer ${NETDATA_FORGEJO_METRICS_TOKEN}"

  - name: synapse
    url: http://element-synapse:9009/_synapse/metrics

  - name: immich-server
    url: http://immich-server:8081/metrics

  - name: livekit
    url: http://element-livekit:6789/metrics

  - name: technitium
    url: http://technitium:5380/api/dashboard/metrics/text
    headers:
      Authorization: "Bearer ${NETDATA_TECHNITIUM_METRICS_TOKEN}"
