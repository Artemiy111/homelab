# RUNBOOK: velero

## Первый запуск

Приложение в Argo — `velero` (проект upstream, namespace velero). Появится после
merge в main; Argo подхватит сам.

Проверка на живом стенде:

```sh
kubectl -n velero get deploy,ds
# ожидаемо: deployment velero 1/1, daemonset node-agent с 1 готовым подом

kubectl get crd | grep velero
# ожидаемо: backups.velero.io, restores.velero.io, schedules.velero.io,
# backupstoragelocations.velero.io, volumesnapshotlocations.velero.io

kubectl -n velero logs deploy/velero --tail=20
# ожидаемо: старт без ошибок; предупреждение об отсутствии BSL — норма фазы 1
```

## Что работает, а что нет

Работает: контроллер, node agent, CRD, CSI-фича включена.

Не работает до BSL (фаза 2): `velero backup create`, `velero restore` и
`velero schedule create` — без BackupStorageLocation все команды падают с
ошибкой. Это ожидаемо и запланировано.

## Обновление версии

Версия чарта — `targetRevision` в `clusters/casa/argocd/platform/velero.yaml`;
образы тянутся из чарта. Апгрейд — правка этой строки после изучения release
notes нового minor. После merge проверять job `velero-upgrade-crds`: при его
сбое CRD обновляются раньше кода приложения, а Application может остаться
Healthy при нерабочей установке.

## Удаление

Убрать `clusters/casa/argocd/platform/velero.yaml` (и каталог юнита) из репо —
Argo почистит ресурсы, кроме CRD (Prune=false их не трогает). CRD и job'ы —
осознанная ручная чистка, если cluster уходит целиком.
