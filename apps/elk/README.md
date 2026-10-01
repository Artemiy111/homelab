# ELK (выведен из эксплуатации)

Стек логов Elasticsearch + Kibana + Filebeat. Заменён на Loki + Grafana Alloy
(`apps/loki/`, `apps/alloy/`): логи теперь идут в Loki и смотрятся в Grafana,
второй бэкенд логов не нужен.

**Манифесты в этом каталоге оставлены как есть, но не применяются.** Чтобы
вернуть стек, нужно заново применить `apps/elk/k8s/` (оператор ECK остаётся
установленным в namespace `elastic-system` через `argocd/applications/eck-operator.yaml`).

## Что удаляется из кластера

`Elasticsearch` и `Beat` CR вместе с подами уже удалены; логи читает Alloy.
Остаётся остаток — Kibana CR (`elk`, развёрнут в 0 реплик) и её Service:

```sh
kubectl delete kibana elk -n logging
kubectl -n logging get all
```

Namespace `logging` после этого пуст. Маршрут `kibana.example.com` удалён
вместе с `IngressRoute` — переносить его на `HTTPRoute` незачем, сервис
выведен из эксплуатации. Namespace разбирается вместе с `apps/elk` в #617.

## Почему не оставили

- один бэкенд логов вместо двух: меньше ресурсов на одноузловом кластере;
- Grafana становится единым UI для метрик, логов и трейсов, корреляция сигналов
  (exemplars, trace↔log) не пересекает два разных интерфейса;
- Alloy отдаёт логи в Loki без Filebeat и Elasticsearch.
