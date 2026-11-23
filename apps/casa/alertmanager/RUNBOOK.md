# Alertmanager: операции с демо-инстансом

## Проверка после развёртывания

Ожидаемый результат: под готов, эндпоинты здоровья отвечают, Secret с темой
существует (значение не выводим).

```sh
kubectl -n monitoring rollout status deploy/alertmanager
kubectl -n monitoring get secret grafana-ntfy
kubectl -n monitoring exec deploy/alertmanager -- wget -qO- http://localhost:9093/-/ready
```

Если под стоит в `CreateContainerConfigError`, проверь, что в неймспейсе
`monitoring` есть Secret `grafana-ntfy` с ключом `NTFY_TOPIC`: его создаёт
`VaultStaticSecret` из юнита Grafana. Если под падает сразу после старта, смотри
логи контейнера `alertmanager` — он отказывается стартовать при невалидном
`alertmanager.yml`. Содержимое этого файла в логи и в issue не копировать: там
лежит тема ntfy.

## Отправка тестовых алертов

Один запрос отправляет два алерта с одинаковыми `alertname` и `namespace`, но
разной `severity`. Ожидаемый результат: в ntfy приходит одно уведомление с
текстом `demo critical` — warning подавлен правилом `inhibit_rules`.

```sh
kubectl -n monitoring exec deploy/alertmanager -- wget -qO- \
  --header='Content-Type: application/json' \
  --post-data='[{"labels":{"alertname":"DemoAlert","severity":"warning","namespace":"monitoring"},"annotations":{"summary":"demo warning"}},{"labels":{"alertname":"DemoAlert","severity":"critical","namespace":"monitoring"},"annotations":{"summary":"demo critical"}}]' \
  http://alertmanager.monitoring.svc.cluster.local:9093/api/v2/alerts
```

Посмотреть, что Alertmanager держит в памяти, можно через `amtool` из того же
образа:

```sh
kubectl -n monitoring exec deploy/alertmanager -- \
  /bin/amtool --alertmanager.url=http://localhost:9093 alert list
```

Повтори тот же запрос сразу после первого: в течение интервала группировки новое
уведомление не придёт — алерты попадут в уже существующую группу. Чтобы увидеть
разгрузку, отправь алерт с другим `alertname`: он создаст новую группу и новое
уведомление. Через таймаут разрешения активные алерты закрываются сами, и при
включённой отправке разрешённых приходит сообщение о снятии.

## UI и тишины

```sh
kubectl -n monitoring port-forward svc/alertmanager 9093:9093
```

Открой `http://localhost:9093`. Вкладка `Alerts` показывает активные алерты и
их группы, `Status` — загруженный конфиг и версию, `Silences` — тишины. Чтобы
проверить тишину: создай её во вкладке `Silences` с матчером `alertname=DemoAlert`
на ближайшее время, отправь тестовый алерт ещё раз и убедись, что уведомления в
ntfy нет. Затем удали тишину там же. После рестарта пода тишина исчезнет —
состояние хранится в `emptyDir`.

## Изменение конфига

Конфиг меняется в Git: Argo обновит ConfigMap, но init-контейнер перечитает его
только при старте пода. Поэтому после синхронизации сделай рестарт:

```sh
kubectl -n monitoring rollout restart deploy/alertmanager
kubectl -n monitoring rollout status deploy/alertmanager
```

Тема ntfy подставляется из Secret'а при каждом старте, поэтому рестарт
обязателен и после ротации темы. Проверить синтаксис можно командой
`amtool check-config /etc/alertmanager/alertmanager.yml` внутри пода; вывод с
реальным значением темы никуда не копировать.

## Удаление демо

Удали файл `Application` из `clusters/casa/argocd/apps/`, перегенерируй
`kustomization.yaml` через `./scripts/argocd-units.sh` и убери каталог юнита.
PVC и других долгоживущих ресурсов у демо нет, поэтому после синхронизации в
кластере ничего не останется.
