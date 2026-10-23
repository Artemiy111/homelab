# casa-edge: эксплуатация

## Первый запуск

Под не поднимется, пока нет Secret с адресом назначения: `socat` берёт его из
переменной окружения и без неё падает.

```sh
kubectl -n casa-edge create secret generic casa-edge-target \
  --from-literal=target=<tailnet-адрес casa>:443
```

Адрес — тот, по которому `casa` виден из tailnet (Tailscale-адрес узла, не
LAN-адрес). Проверить с узла `yc`:

```sh
ssh <логин OS Login>@yc-d1 'tailscale ping <имя узла casa>'
```

`ping` отвечает `pong` — значит маршрут есть и адрес годится.

После создания Secret под перезапускать не нужно: переменная окружения
подставляется при старте, поэтому если под уже падал в `CreateContainerConfigError`:

```sh
kubectl -n casa-edge rollout restart deploy/casa-edge
```

## Проверка

```sh
kubectl -n casa-edge get pods,svc
kubectl -n casa-edge logs deploy/casa-edge --tail=20
```

Ожидается под `Running` и `1/1` (readiness-проба слушает порт), в логах `socat`
— строки о принятых соединениях на каждый запрос снаружи.

Снаружи (не из дома и не из tailnet):

```sh
curl -sI https://uptime.ts.biplane.casa/
openssl s_client -connect uptime.ts.biplane.casa:443 -servername uptime.ts.biplane.casa </dev/null \
  | openssl x509 -noout -subject -dates
```

Ожидается `200`/`302` и сертификат на `*.ts.biplane.casa` от Let's Encrypt.

Если порт не отвечает, проверять по порядку:

1. `terraform output` в `infra/yc/terraform/cluster` — у балансировщика есть
   слушатель `443` на `edge_node_port`, в группе безопасности открыт этот порт.
2. `kubectl -n casa-edge get svc casa-edge` — NodePort совпадает с
   `edge_node_port` в Terraform.
3. `kubectl -n casa-edge get endpoints casa-edge` — адрес пода в списке; пустой
   список значит, что readiness-проба не проходит.
4. С узла `yc`: `curl -sI https://<tailnet-адрес casa>/ -H 'Host: uptime.ts.biplane.casa'`
   — если не отвечает, проблема не в облаке, а в tailnet или в Traefik.

## Смена адреса назначения

Например, после пересоздания узла `casa` — tailnet-адрес у нового узла другой.

```sh
kubectl -n casa-edge create secret generic casa-edge-target \
  --from-literal=target=<новый tailnet-адрес>:443 \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n casa-edge rollout restart deploy/casa-edge
```

## Удаление

Снимается вместе с юнитом: убрать `apps/yc/casa-edge.yaml` из
`clusters/yc/kustomization.yaml` — Flux удалит Deployment и Service, но не
namespace (`prune: disabled`). Затем `kubectl delete ns casa-edge`.

В `infra/yc/terraform/cluster` слушатель `443` и правило на `edge_node_port`
убираются отдельным коммитом, иначе балансировщик продолжит отдавать порт в
никуда. После этого — запись `*.ts.biplane.casa` в Spaceship.
