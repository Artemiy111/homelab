# Falco: эксплуатация

## Что считать признаком работы

```sh
kubectl -n falco get ds falco
kubectl -n falco get pods
```

Ожидаемо: `READY 1/1` и под без рестартов. Тишина в логе признаком работы не
является: Falco пишет только сработавшие правила, поэтому при нуле событий лог
пуст — «нет вывода» и «нет детекта» это не одно и то же. Проверять надо
счётчики, а не лог.

```sh
kubectl -n monitoring port-forward svc/victoriametrics 8428:8428 &
curl -sG http://localhost:8428/api/v1/query --data-urlencode 'query=falcosecurity_scap_n_evts_total' | jq -r '.data.result[0].value[1]'
curl -sG http://localhost:8428/api/v1/query --data-urlencode 'query=falcosecurity_scap_n_evts_total' | jq -r '.data.result[0].value[1]'
curl -sG http://localhost:8428/api/v1/query --data-urlencode 'query=falcosecurity_scap_n_drops_total' | jq -r '.data.result[0].value[1]'
curl -sG http://localhost:8428/api/v1/query --data-urlencode 'query=falcosecurity_falco_rules_matches_total' | jq -r '.data.result[] | "\(.metric.rule_name)\t\(.value[1])"'
kill %1
```

Ожидаемо: первое число растёт между двумя вызовами (события идут), `drops` равен
нулю, в последнем списке — правила с ненулевыми счётчиками. Пустой ответ по
`scap_n_evts_total` означает, что либо метрики не собираются, либо цель не
скрейпится; ненулевой `scap_n_drops_total` — что часть событий до Falco не
доходит и наблюдение неполное.

## Проверка метаданных контейнеров

```sh
kubectl -n falco logs -l app.kubernetes.io/name=falco -c falco --tail=200 | grep -o 'k8s_ns_name=[^ ]*' | sort -u
```

Ожидаемо: имена namespace'ов. `<NA>` означает, что container-плагин не
подключился к рантайму узла, и событие бесполезно для разбора.

## Контролируемый триггер

Проверка «ловит ли он вообще» не должна ждать удобного случая.

```sh
kubectl run falco-canary --image=busybox:1.36 --restart=Never --command -- sh -c 'cp /bin/busybox /dev/shm/canary && /dev/shm/canary true'

kubectl -n falco logs -l app.kubernetes.io/name=falco -c falco --tail=20 | grep 'Execution from /dev/shm'

kubectl delete pod falco-canary
```

Ожидаемо: `Warning File execution detected from /dev/shm` с заполненными
`k8s_pod_name=falco-canary`, `k8s_ns_name=default` и
`container_image_repository=busybox`. Событие без метаданных pod'а — та же
проблема плагина, что выше.

## Перевод ручного Helm-релиза под Argo

Юнит рассчитан на то, что ресурсы namespace создаёт Argo, а не Helm. Если Falco
оказался здесь после ручного `helm install`, порядок такой же, как в
[`../argocd/RUNBOOK.md`](../argocd/RUNBOOK.md): применить `Application`,
убедиться, что `argocd app diff falco` показывает только ожидаемое, синкнуть
(серверный apply забирает владение объектами) и «забыть» Helm-релиз, чтобы
`helm upgrade` больше не конкурировал с Argo:

```sh
kubectl -n falco delete secret -l owner=helm,name=falco
helm list -n falco
```

Ожидаемо: `helm list` пуст, под и объекты на месте.

## Обновление версии

Версия образа — `image.tag` в `values.yaml`; версия чарта —
`spec.sources[].targetRevision` в `Application`. Обе меняются одним PR.

```sh
kubectl -n argocd get application falco -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{"\n"}'
```

Ожидаемо после синка: `Synced Healthy`. Обновление тега образа меняет под: на
одноузловом стенде это короткий разрыв в наблюдении, а не потеря данных —
проверить после синка, что под поднялся (`kubectl -n falco get pods`) и что
`scap_n_evts_total` снова растёт.

Перед бампом версии ядра или Falco стоит сверить, что выбранная версия вообще
грузит пробу на этом ядре: отказ виден только в логе пода (см. таблицу ниже),
Health-статус Argo в этот момент ещё `Progressing`.

## Удаление

Финалайзера на `Application` нет, поэтому удаление приложения ресурсы не тронет:

```sh
kubectl delete -f clusters/casa/platform/falco/app.yaml
kubectl -n falco get all,cm,role,rolebinding,sa
kubectl delete namespace falco
```

Ожидаемо: после первого шага поды остаются на месте (это и проверяется вторым
шагом), поэтому namespace удаляется руками. Остатки Helm-релиза, если его не
забыли на этапе адопции, снимаются `helm uninstall -n falco falco` — до удаления
namespace.

## Диагностика

| Симптом | Причина и что смотреть |
|---|---|
| под в `CrashLoopBackOff`, в логе `BPF program load failed` и `invalid mem access 'scalar'` | ядро узла несовместимо с версией Falco: проба не прошла верификатор, Falco вышел из `scap_init`. Смотреть `kubectl -n falco logs <pod> -c falco \| tail -40`; версия образа должна быть не ниже той, где есть фикс (см. README) |
| события без `k8s_pod_name` и `k8s_ns_name` | container-плагин не подключился: в логе `container engine unavailable`; проверить сокет рантайма в `collectors` и `kubectl -n falco get ds falco -o jsonpath='{.spec.template.spec.volumes}'` |
| в VictoriaMetrics нет `falcosecurity_*` | метрики выключены в values, нет Service `falco-metrics` или не обновился scrape-конфиг vmagent: `kubectl -n monitoring get cm vmagent-scrape -o yaml \| grep -A3 falco` и `kubectl -n monitoring logs deploy/vmagent \| grep falco` |
| `scap_n_drops_total` растёт | буфер не успевает за потоком событий: поднять `driver.modernEbpf.bufSizePreset` или уменьшить `cpusForEachBuffer` |
| `rules_matches_total` пуст, событий в логе нет | сначала посмотреть `scap_n_evts_total`: если он растёт — просто нет совпадений с правилами, если стоит — не работает проба |
| событий больше, чем ожидалось | штатный набор правил не настроен под стенд: это состояние до задачи про исключения, а не поломка |

## Источники

- [Правила Falco по умолчанию](https://github.com/falcosecurity/rules)
- [Unsupported kernels и выбор пробы](https://falco.org/docs/concepts/event-sources/kernel/)
- [Метрики Falco](https://falco.org/docs/concepts/metrics/)
