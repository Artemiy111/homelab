# casa-edge: эксплуатация

## Первый запуск

Под не поднимется, пока нет Secret с адресом назначения: `HAProxy` берёт его из
переменной окружения и без неё падает.

```sh
kubectl -n casa-edge create secret generic casa-edge-target \
  --from-literal=target=<домашний адрес ingress>:8443
kubectl -n casa-edge rollout restart daemonset/casa-edge
```

Адрес — тот, по которому `casa` отдаёт HTTPS из домашней сети (внешний адрес
Traefik), а не tailnet-адрес узла: на tailnet-адресе открыт только SSH. Порт —
entrypoint `edge`, который принимает PROXY protocol. Проверить с узла `yc`, что
маршрут до домашней подсети есть:

```sh
ssh <логин OS Login>@yc-d1 'tailscale status | head -3; ping -c1 <домашний адрес ingress>'
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
ssh <логин OS Login>@yc-d1 'ss -ltn | grep -E ":(443|8443)"'
```

Снаружи (не из дома и не из tailnet):

```sh
curl -sI https://uptime.biplane.casa/
openssl s_client -connect uptime.biplane.casa:443 \
  -servername uptime.biplane.casa </dev/null | openssl x509 -noout -subject -dates
```

Ожидается `200`/`302` и сертификат на `*.biplane.casa` от Let's Encrypt.

Если порт не отвечает, проверять по порядку:

1. `terraform output` в `infra/yc/terraform/cluster` — у балансировщика есть
   слушатель `443` с `target_port` из `edge_port`, в группе безопасности открыт
   тот же порт.
2. `kubectl -n casa-edge get pods` — под на каждом узле запущен; под в
   `CreateContainerConfigError` значит нет Secret.
3. С узла `yc`: `curl -sI https://<tailnet-адрес casa>/ -H 'Host: uptime.biplane.casa'`
   — если не отвечает, проблема не в форвардере, а в tailnet или в Traefik.
4. В логах пода `HAProxy` печатает ошибки разбора конфига и недоступность
   апстрима. Заголовок PROXY protocol виден не здесь, а в Traefik: если он не
   пришёл, entrypoint `edge` отвечает ошибкой TLS вместо страницы.

## Смена адреса назначения

Например, после пересоздания узла `casa` — tailnet-адрес у нового узла другой.

```sh
kubectl -n casa-edge create secret generic casa-edge-target \
  --from-literal=target=<новый tailnet-адрес>:8443 \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n casa-edge rollout restart daemonset/casa-edge
```

## Удаление

Снимается вместе с юнитом: убрать `apps/yc/casa-edge.yaml` из
`clusters/yc/kustomization.yaml` — Flux удалит DaemonSet, но не namespace
(`prune: disabled`). Затем `kubectl delete ns casa-edge`.

В `infra/yc/terraform/cluster` слушатель `443` и правило на `edge_port` убираются
отдельным коммитом, иначе балансировщик продолжит отдавать порт в никуда. После
этого — запись `*.biplane.casa` в Spaceship.
