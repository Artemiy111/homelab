# envoy-gateway

Точка входа HTTP и HTTPS для кластера `yc`: [Envoy Gateway](https://gateway.envoyproxy.io) и Gateway API. Приложения объявляют маршруты объектами `HTTPRoute`, а не собственным NodePort.

## Как устроен доступ

```
клиент :80  → NLB → NodePort 30081 на узле → под Envoy → HTTPRoute по Host → Service приложения
клиент :443 → NLB → casa-edge :8443 → по SNI:
    *.yc.clusters.biplane.casa → NodePort 30082 → под Envoy (TLS) → HTTPRoute
    остальное                  → домашний Traefik (TLS там же)
```

Балансировщик работает на L4 и про Gateway не знает: он просто передаёт трафик на NodePort, который открывает `Service` Envoy. Поэтому в облаке нет ни `type: LoadBalancer` (без cloud-controller-manager он навсегда остался бы `<pending>`), ни `externalIPs`.

NodePort зафиксированы патчем в `EnvoyProxy` (`30081` для HTTP, `30082` для HTTPS) — иначе они были бы случайными, и ни Terraform, ни `casa-edge` не смогли бы на них сослаться. `30081` лежит в `gateway_node_port` в `infra/yc/terraform/cluster/main.tf`; менять только вместе.

`externalTrafficPolicy: Cluster`, а не умолчательный `Local`. С `Local` kube-proxy открывает NodePort только на узлах, где стоит под Envoy, а балансировщик считает живыми все три узла (его health-чек — TCP `6443`, общий для двух слушателей) и две трети соединений отправляет в таймаут. За реальный IP клиента эта настройка не платит: Envoy видит адрес узла. Вернуть `Local` можно только вместе с отдельным health-чеком на `30081`, а он требует второй целевой группы, то есть второго балансировщика.

Envoy запускается в двух репликах: одна реплика на весь кластер — это единая точка отказа для всего HTTP.

Новому приложению нужен только `HTTPRoute` со своим `hostnames`: DNS-записи заводятся не под каждое имя, в зоне кластера стоит wildcard `*.yc.clusters.biplane.casa` (одного уровня, точная запись `api` главнее). Имя без маршрута получит `404` от Envoy.

## Поставка чартом, а не `install.yaml`

Раньше здесь лежал `manifests/install.yaml` — релизный артефакт «Install with YAML» на 63 тысячи строк. Обновление версии означало замену этих строк и невозможность увидеть в диффе, что изменилось.

Теперь стоит официальный Helm-чарт из OCI:

| Файл | Что объявляет |
| --- | --- |
| `releases/ocirepository.yaml` | `OCIRepository` на `oci://docker.io/envoyproxy/gateway-helm`, тег `v1.9.2` |
| `releases/helmrelease.yaml` | `HelmRelease`, который ставит чарт в `envoy-gateway-system` |
| `config/gateway.yaml` | `GatewayClass`, `EnvoyProxy` с NodePort, `Gateway` на портах 80 и 443 |

Версия живёт в одном месте — `ref.tag` у `OCIRepository`.

### Почему CRD не отдельным релизом

Апстрим публикует два чарта: `gateway-helm` (контроллер) и `gateway-crds-helm` (только CRD). Второй нужен тем, кто управляет CRD независимо от контроллера: свой канал Gateway API (standard или experimental) или несколько контроллеров на кластер.

У `gateway-helm` CRD уже внутри — сабчартом в каталоге `crds/`. Helm такой каталог ставит, но при обновлении не трогает, поэтому в `HelmRelease` включён `crds: CreateReplace`: Flux переприменяет CRD через server-side apply на каждой ревизии. Удаление релиза CRD при этом не сносит — Helm не удаляет `crds/`, а значит `Gateway` и `HTTPRoute` переживут снятие контроллера.

Отдельный `gateway-crds-helm` для нас хуже: его CRD — обычные шаблоны, и `helm uninstall` уносит их вместе со всеми объектами Gateway API в кластере.

## TLS

Сертификат на `*.yc.clusters.biplane.casa` выпускает Yandex Certificate Manager
(модуль `infra/yc/terraform/tls`): Let's Encrypt, DNS-01 в зоне `yc`. Содержимое
в кластер кладётся вручную — Certificate Manager продлевает сертификат сам, но
Secret не обновляет:

```sh
yc certificate-manager certificate content --name yc-wildcard \
  --chain /tmp/yc-wildcard.crt --key /tmp/yc-wildcard.key > /dev/null

kubectl -n envoy-gateway-system create secret tls yc-wildcard-tls \
  --cert=/tmp/yc-wildcard.crt --key=/tmp/yc-wildcard.key

rm /tmp/yc-wildcard.crt /tmp/yc-wildcard.key
```

Listener `https` ссылается на этот Secret. Порт 443 снаружи принадлежит
`casa-edge`: он разбирает SNI и отдаёт имена `*.yc.clusters.biplane.casa` на
NodePort `30082`, остальное — в домашний Traefik. Поэтому Gateway не слушает 443
напрямую, а `HTTPRoute` без `sectionName` попадает на оба listener'а.

Продление Certificate Manager делает сам; Secret нужно пересоздать из нового
содержимого, иначе Gateway продолжит отдавать старый сертификат. Пока это ручной
шаг.

## Проверка

```sh
kubectl -n envoy-gateway-system get pods
kubectl get gatewayclass eg
kubectl -n envoy-gateway-system get gateway yc
kubectl get httproute -A
kubectl -n envoy-gateway-system get svc          # envoy-...: NodePort 30081
flux -n flux-system get helmrelease,ocirepository
```

`Gateway` в статусе `Programmed`, `HTTPRoute` — `Accepted` и `ResolvedRefs`.

## Чего здесь нет

- **Виртуальных хостов сверх Host-маршрутизации.** Пути и заголовки Gateway API умеет, но пока это не нужно.
- **Настоящего health-чека для HTTP.** У балансировщика одна целевая группа на две службы (адрес не может быть в двух группах в Yandex Cloud), проверка доступности — TCP `6443` на kube-api. Значит «жив ли Envoy» балансировщик не знает.
- **PROXY protocol на HTTPS-listener.** `casa-edge` передаёт TLS как есть, поэтому Envoy видит адрес узла, а не клиента; для домашних имён клиентский IP по-прежнему доезжает через PROXY protocol.
