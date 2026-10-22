# Beyla: эксплуатация

## Включение и выключение

Beyla запускается только на узлах с лейблом `homelab.io/beyla=enabled`.
Включить на узле:

```sh
kubectl label node homelab homelab.io/beyla=enabled
kubectl -n monitoring get ds beyla    # DESIRED 1, READY 1
```

Выключить, сняв лейбл:

```sh
kubectl label node homelab homelab.io/beyla-
kubectl -n monitoring get ds beyla    # DESIRED 0
```

Лейбл живёт на узле, а не в git: после пересоздания узла Beyla останется
выключенной, пока лейбл не поставят снова. Argo при этом остаётся `Synced`.

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
