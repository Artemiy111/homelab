# mihomo: эксплуатация

## Первый запуск

Перед деплоем в Vault должна быть записана подписка. Политика `app/mihomo`
выдаёт доступ только к точному пути `kv/mihomo/subscription`, роль `mihomo`
привязана к ServiceAccount `vso-mihomo` в namespace `mihomo`; и то и другое
управляется Terraform в `infra/casa/terraform/vault/`.

```sh
vault kv put kv/mihomo/subscription SUBSCRIPTION_URL='<subscription-url>'
```

Если секрета нет, под `mihomo-subconv` не стартует: контейнер моста ждёт смонтированный
файл с ключом `SUBSCRIPTION_URL`.

## Проверка на стенде

Убедиться, что поды запущены:

```sh
kubectl -n mihomo get pods
```

Проверить, что ключ в секрете называется правильно (значение не печатается):

```sh
kubectl -n mihomo get secret mihomo-subscription -o json | jq -r '.data | keys[]'
```

Проверить, что конвертер отдаёт Clash YAML с узлами:

```sh
kubectl -n mihomo exec deploy/mihomo-subconv -c bridge -- \
  python -c 'import urllib.request as u; r=u.urlopen("http://127.0.0.1:8081/provider", timeout=30); print(r.status, len(r.read()))'
```

Ожидаемый результат: `200` и ненулевой размер тела. Нулевой список `proxies`
означает, что подписка просрочена или вернула пустой ответ.

Проверить, что mihomo загрузил провайдер и узлы здоровы:

```sh
kubectl -n mihomo port-forward svc/mihomo 9090:9090 &
curl -fsS http://127.0.0.1:9090/providers/proxies | jq '.providers.happ'
```

В выводе должен быть непустой список `proxies` с `alive: true` у части узлов.

Проверить проксирование через mihomo:

```sh
kubectl -n mihomo exec deploy/mihomo-subconv -c bridge -- \
  python -c 'import urllib.request as u; p=u.ProxyHandler({"http":"http://mihomo.mihomo.svc.cluster.local:7890","https":"http://mihomo.mihomo.svc.cluster.local:7890"}); print(u.build_opener(p).open("https://example.com", timeout=15).status)'
```

Ожидаемый результат: `200`.

Убедиться, что 3x-ui не тронут и продолжает обслуживать Renovate и Gatus —
проверка egress-чека в Gatus и обычный прогон Renovate.

## Обновление подписки

```sh
vault kv put kv/mihomo/subscription SUBSCRIPTION_URL='<new-url>'
```

`VaultStaticSecret` обновит Kubernetes Secret в течение часа, смонтированный файл
подхватит новое значение, а мост читает его при каждом запросе — рестарт пода
не нужен. mihomo перезагрузит провайдер по своему интервалу; чтобы ускорить,
можно вызвать `PUT /providers/proxies/happ` через `external-controller`.

## Известные сбои

- **Под висит в `CreateContainerConfigError`.** Нет Secret `mihomo-subscription`
  или в нём нет ключа `SUBSCRIPTION_URL`. Записать подписку заново.
- **Мост отдаёт `502`.** SubConv не смог скачать подписку: просрочен URL,
  истёк сертификат или подписка вернула не share-ссылки. Проверить мост и SubConv
  отдельно, не меняя 3x-ui.
- **Узлы `alive: false`.** Проверить health-check URL и доступность самих узлов.
  Это не влияет на 3x-ui.
- **В логах mihomo ошибки загрузки провайдера.** Проверить, что Service
  `mihomo-subconv` резолвится полным именем и что мост отвечает на `/provider`.

## Удаление

mihomo — параллельный юнит, удаление не затрагивает потребителей. Удалить
`Application` из `clusters/casa/argocd/apps/`, перегенерировать kustomization,
затем вручную удалить namespace `mihomo`: у него стоит `Prune=false`, поэтому
Argo его не тронет. Политику и роль в Vault удалить из Terraform только после
того, как секрет больше не нужен.
