# OpenCost: эксплуатация

## Проверка на стенде

Под и приложение в Argo:

```sh
kubectl -n opencost get pods
kubectl -n argocd get application opencost
```

Ожидается под `Running`/`Ready` и приложение `Synced`/`Healthy`.

API отдаёт allocations:

```sh
kubectl -n opencost port-forward svc/opencost 9003
```

В другом терминале:

```sh
curl -sS 'http://127.0.0.1:9003/allocation/compute?window=24h' | jq '.data[0] | length'
```

Ожидается число больше нуля — столько namespace попало в ответ. Пустой ответ
означает, что считаются не метрики, а не то, что Lens настроен неверно: смотреть
раздел «Allocation пустой».

## Lens

Настройки кластера → **Cost** → **Source**:

- **Automatic** — Lens сам находит OpenCost и пишет `Using OpenCost`.
- **OpenCost** — если автопоиск не сработал, адрес `opencost/opencost:9003`.

Ожидается статус `Found at opencost/opencost:9003`, разбивка по namespace и
ненулевые Storage и Network. Если Lens показывает только CPU и Memory, он
считает Estimate: значит, OpenCost не найден или недоступен.

## Переключение прайс-пресета

В манифесте Deployment значение `PRICING_CONFIGMAP_NAME` меняется на
`custom-pricing-yandex` или назад на `custom-pricing-aws`. Изменение едет обычным
PR; Argo применяет его, и под перезапускается, потому что переменная окружения
изменилась.

Проверка, что применилось:

```sh
kubectl -n opencost get deploy opencost -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="PRICING_CONFIGMAP_NAME")].value}{"\n"}'
```

Ожидается имя выбранного ConfigMap.

## Обновление цен

Ставки правятся в `data` соответствующего ConfigMap. OpenCost следит за
ConfigMap прайса и перечитывает его без перезапуска; если цифры в API не
изменились в течение пары минут, под перезапускается вручную:

```sh
kubectl -n opencost rollout restart deploy/opencost
```

Проверять тем же запросом allocations, что и в «Проверка на стенде».

## Обновление версии

Обновляется тег и digest образа в Deployment. Вместе с версией сверяются правила
ClusterRole с `clusterrole.yaml` upstream-чарта OpenCost: набор ресурсов между
версиями меняется, а лишнее право так же плохо, как отсутствующее. После
раскатки — проверка на стенде.

## Диагностика

### Allocation пустой

Источник данных отвечает и метрики в нём есть:

```sh
kubectl -n opencost exec deploy/opencost -- wget -qO- \
  'http://victoriametrics.monitoring.svc.cluster.local:8428/api/v1/query?query=container_cpu_usage_seconds_total' | head -c 200
kubectl -n monitoring exec deploy/victoriametrics -- wget -qO- \
  'http://127.0.0.1:8428/api/v1/query?query=up{job=~"cadvisor|kubelet|kube-state-metrics"}' | grep -o '"job":"[^"]*"'
```

Первый запрос должен вернуть непустой результат, второй — три job'а. Если
метрик нет, смотреть scrape-конфиг vmagent, а не OpenCost.

Логи самого OpenCost:

```sh
kubectl -n opencost logs deploy/opencost --since=10m
```

### Прайс не применился

Ключ, которого нет в модели цен OpenCost, отменяет обновление целиком, а не
одну строку. В логах это `error setting custom pricing field`: сверить ключи
ConfigMap с полями модели `CustomPricing` в OpenCost (регистр первой буквы
значения не имеет).

### Lens не видит источник

Проверить, что сервис отвечает через port-forward (см. «Проверка на стенде»),
и задать адрес `opencost/opencost:9003` в настройках Cost вручную. Проверить,
что NetworkPolicy namespace'а `opencost` пускает трафик с адреса узла: Lens
ходит в сервис через port-forward, и источником оказывается узел, а не pod.

## Удаление

Сначала убрать каталог юнита из репозитория, чтобы Application не вернул
удалённое, затем снести namespace и кластерные объекты:

```sh
kubectl delete namespace opencost
kubectl delete clusterrole opencost
kubectl delete clusterrolebinding opencost
```
