# local-path-provisioner: эксплуатация

## Проверка

```sh
kubectl -n local-path-storage get pods
kubectl get storageclass local-path
kubectl get pv
```

Ожидаемо: под `local-path-provisioner-*` в `Running`, класс `local-path`
помечен `(default)`, у созданных PVC есть PV в `Bound`.

## Диагностика

**PVC висит в `Pending`.** Смотреть события: `kubectl describe pvc <имя> -n
<namespace>`. Пока нет пода-потребителя, `WaitForFirstConsumer` держит PVC в
`Pending` — это норма, а не сбой. Если под уже есть, причина обычно в
недоступности узла или в том, что helper-под не смог создать каталог.

**Под с томом висит в `Pending` после выхода узла.** Том привязан к узлу. Вернуть
узел в строй или перенести данные вручную; автоматического переезда нет.

**`DiskPressure` на узле.** Проверить занятое место:

```sh
kubectl -n local-path-storage logs deploy/local-path-provisioner --tail=100
kubectl get node <узел> -o jsonpath='{.status.conditions[?(@.type=="DiskPressure")].status}'
```

Освобождать место в `/opt/local-path-provisioner` на узле можно только после
удаления PVC: иначе провижионер считает каталог живым.

## Обновление версии

Манифесты — копия `deploy/local-path-storage.yaml` из тега
`rancher/local-path-provisioner`. Обновление — новый тег и digest в
`deployment.yaml` и `configmap.yaml` (образ helper-пода), затем проверка, что
существующие тома монтируются.

## Удаление

`kubectl delete -k platform/yc/local-path-provisioner/manifests` уносит
провижионер, но не тома: PVC и каталоги на узлах остаются. Удалять класс вместе
с томами нельзя — PVC, созданные им, станут `Pending` навсегда.
