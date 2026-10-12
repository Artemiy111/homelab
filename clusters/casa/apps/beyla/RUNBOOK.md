# Beyla: эксплуатация

## Проверка

```sh
# поды
kubectl -n monitoring get pods -l app=beyla

# RED-метрики дошли до VictoriaMetrics
up{job="otel-collector"}                       # otel-collector уже скрейпится
http_server_request_duration_seconds_count     # метрики Beyla

# трейсы дошли до Tempo
# в Grafana: Explore → Tempo → service name: element-livekit / element-synapse
```
