# ELK (выведен из эксплуатации)

Стек логов Elasticsearch + Kibana + Filebeat. Заменён на Loki + Grafana Alloy
(`apps/casa/loki/`, `apps/casa/alloy/`): логи теперь идут в Loki и смотрятся в Grafana,
второй бэкенд логов не нужен.

Манифесты в этом каталоге оставлены как есть, но не применяются. Оператор ECK
остаётся установленным в namespace `elastic-system`.

Namespace `logging` после этого пуст. Маршрут `kibana.example.com` удалён
вместе с `IngressRoute` — переносить его на `HTTPRoute` незачем, сервис
выведен из эксплуатации. Namespace разбирается вместе с `apps/casa/elk` в #617.

Возврат стека — в `RUNBOOK.md`.
