# ELK (выведен из эксплуатации)

Стек логов Elasticsearch + Kibana + Filebeat. Заменён на Loki + Grafana Alloy
(`clusters/casa/apps/loki/`, `clusters/casa/apps/alloy/`): логи теперь идут в Loki и смотрятся в Grafana,
второй бэкенд логов не нужен.

**Манифесты в этом каталоге оставлены как есть, но не применяются.** Чтобы
вернуть стек, нужно заново применить `clusters/casa/apps/elk/k8s/` (оператор ECK остаётся
установленным в namespace `elastic-system` через `clusters/casa/platform/eck-operator/app.yaml`).
```

Namespace `logging` после этого пуст. Маршрут `kibana.example.com` удалён
вместе с `IngressRoute` — переносить его на `HTTPRoute` незачем, сервис
выведен из эксплуатации. Namespace разбирается вместе с `clusters/casa/apps/elk` в #617.
