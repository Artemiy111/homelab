# casa-edge: эксплуатация

## Первый запуск

Под не поднимется, пока нет Secret с адресом назначения: `socat` берёт его из
переменной окружения и без неё падает.

```sh
kubectl -n casa-edge create secret generic casa-edge-target \
  --from-literal=target=<tailnet-адрес casa>:443
kubectl -n casa-edge rollout restart daemonset/casa-edge
```

Адрес — тот, по которому `casa` виден из tailnet (Tailscale-адрес узла, не
LAN-адрес). Проверить с узла `yc`:

```sh
ssh <логин OS Login>@yc-d1 'tailscale ping <имя узла casa>'
```

`ping` отвечает `pong` — значит маршрут есть и адрес годится.

## Проверка

```sh
kubectl -n casa-edge get pods -o wide
kubectl -n casa-edge logs daemonset/casa-edge --tail=20
```

Ожидается по одному поду на каждый узел в `Running` и `1/1`. Порт слушается на
самом узле, поэтому проверяется там, а не в Service:

```sh
ssh <логин OS Login>@yc-d1 'ss -ltn | grep :443'
```

Снаружи (не из дома и не из tailnet):

```sh
curl -sI https://uptime.ts.biplane.casa/
openssl s_client -connect uptime.ts.biplane.casa:443 \
  -servername uptime.ts.biplane.casa </dev/null | openssl x509 -noout -subject -dates
```

Ожидается `200`/`302` и сертификат на `*.ts.biplane.casa` от Let's Encrypt.

Если порт не отвечает, проверять по порядку:

1. `terraform output` в `infra/yc/terraform/cluster` — у балансировщика есть
   слушатель `443` с `target_port` из `edge_port`, в группе безопасности открыт
   тот же порт.
2. `kubectl -n casa-edge get pods` — под на каждом узле запущен; под в
   `CreateContainerConfigError` значит нет Secret.
3. С узла `yc`: `curl -sI https://<tailnet-адрес casa>/ -H 'Host: uptime.ts.biplane.casa'`
   — если не отвечает, проблема не в форвардере, а в tailnet или в Traefik.
4. В логах пода `socat` печатает по строке на соединение. Строки
   `connect ... Operation timed out` значат, что до `casa` не доходит: проверять
   `tailscale status` и одобрение маршрутов на домашнем узле.

## Смена адреса назначения

Например, после пересоздания узла `casa` — tailnet-адрес у нового узла другой.

```sh
kubectl -n casa-edge create secret generic casa-edge-target \
  --from-literal=target=<новый tailnet-адрес>:443 \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n casa-edge rollout restart daemonset/casa-edge
```

## Удаление

Снимается вместе с юнитом: убрать `apps/yc/casa-edge.yaml` из
`clusters/yc/kustomization.yaml` — Flux удалит DaemonSet, но не namespace
(`prune: disabled`). Затем `kubectl delete ns casa-edge`.

В `infra/yc/terraform/cluster` слушатель `443` и правило на `edge_port` убираются
отдельным коммитом, иначе балансировщик продолжит отдавать порт в никуда. После
этого — запись `*.ts.biplane.casa` в Spaceship.
