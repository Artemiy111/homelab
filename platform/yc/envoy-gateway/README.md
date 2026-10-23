# envoy-gateway

Точка входа HTTP для кластера `yc`: [Envoy Gateway](https://gateway.envoyproxy.io) и Gateway API. Приложения объявляют маршруты объектами `HTTPRoute`, а не собственными NodePort.

## Как устроен доступ

```
клиент :80 → NLB → NodePort 30081 на узле → под Envoy → HTTPRoute по Host → Service приложения
```

Балансировщик работает на L4 и про Gateway не знает: он просто передаёт трафик на NodePort, который открывает `Service` Envoy. Поэтому в облаке нет ни `type: LoadBalancer` (без cloud-controller-manager он навсегда остался бы `<pending>`), ни `externalIPs`.

NodePort зафиксирован патчем в `EnvoyProxy` (`30081`) — иначе он был бы случайным, и Terraform не смог бы на него сослаться. Тот же порт лежит в `gateway_node_port` в `infra/yc/terraform/cluster/main.tf`; менять только вместе.

`externalTrafficPolicy: Cluster`, а не умолчательный `Local`. С `Local` kube-proxy открывает NodePort только на узлах, где стоит под Envoy, а балансировщик считает живыми все три узла (его health-чек — TCP `6443`, общий для двух слушателей) и две трети соединений отправляет в таймаут. За реальный IP клиента эта настройка не платит: Envoy видит адрес узла. Вернуть `Local` можно только вместе с отдельным health-чеком на `30081`, а он требует второй целевой группы, то есть второго балансировщика.

Envoy запускается в двух репликах: одна реплика на весь кластер — это единая точка отказа для всего HTTP.

## Что здесь лежит

| Часть | Зачем |
| --- | --- |
| `manifests/install.yaml` | официальный `install.yaml` релиза: CRD Gateway API, CRD Envoy Gateway, контроллер |
| `config/gateway.yaml` | `GatewayClass`, `EnvoyProxy` с NodePort и `Gateway` на порту 80 |
| `manifests/kustomization.yaml`, `config/kustomization.yaml` | сборка для двух Flux `Kustomization` |

Разделение на два каталога не косметическое: CRD должны существовать раньше объектов, поэтому у второй Flux `Kustomization` есть `dependsOn` на первую.

## Проверка

```sh
kubectl -n envoy-gateway-system get pods
kubectl get gatewayclass eg
kubectl -n envoy-gateway-system get gateway yc
kubectl get httproute -A
kubectl -n envoy-gateway-system get svc          # envoy-...: NodePort 30081
```

`Gateway` в статусе `Programmed`, `HTTPRoute` — `Accepted` и `ResolvedRefs`.

## Чего здесь нет

- **TLS.** Только HTTP: сертификаты требуют cert-manager и солвер для Cloud DNS, подзона делегирована туда.
- **Виртуальных хостов сверх Host-маршрутизации.** Пути и заголовки Gateway API умеет, но пока это не нужно.
- **Настоящего health-чека для HTTP.** У балансировщика одна целевая группа на две службы (адрес не может быть в двух группах в Yandex Cloud), проверка доступности — TCP `6443` на kube-api. Значит «жив ли Envoy» балансировщик не знает.
