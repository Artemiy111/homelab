# Nexus: эксплуатация

## Проверка

```sh
kubectl -n nexus get pods
kubectl -n nexus get externalsecret nexus-db
kubectl -n nexus get pvc
curl -s -o /dev/null -w '%{http_code}\n' \
  http://nexus.yc.clusters.biplane.casa/service/rest/v1/status
```

Ожидаемо: под `nexus-*` в `Running`, `ExternalSecret` в `SecretSynced`,
PVC в `Bound`, статус отвечает `200`.

## Первый вход

Пароль администратора генерируется при первом старте и лежит в томе:

```sh
kubectl -n nexus exec deploy/nexus -- cat /nexus-data/admin.password
```

Логин `admin`; после входа Nexus попросит сменить пароль. Пароль из файла после
этого недействителен.

## Секрет базы

Пароль приходит из Lockbox. Если под не стартует с ошибкой аутентификации:

```sh
kubectl -n nexus describe externalsecret nexus-db
kubectl -n external-secrets logs deploy/external-secrets --tail=100
```

`PermissionDenied` — у сервисного аккаунта `nexus-lockbox` нет
`lockbox.payloadViewer` на секрет; `Secret does not exist` — не создан `yc-auth`
(см. `platform/yc/external-secrets/RUNBOOK.md`).

После ротации пароля в Lockbox Secret в кластере обновится сам, но под читает
переменную окружения только при старте:

```sh
kubectl -n nexus rollout restart deploy/nexus
```

## Под висит в Pending

```sh
kubectl -n nexus describe pod -l app=nexus
kubectl -n nexus describe pvc nexus-data
```

Причины по порядку вероятности: не готова база (см. ExternalSecret), том привязан
к узлу, который недоступен, или на узле закончилось место. В последнем случае
`kubectl describe node <узел>` покажет `DiskPressure`.

## Заполнение диска

Blob store растёт вместе с артефактами. Освобождать место — задачами очистки
внутри Nexus (Cleanup Policies), а не удалением файлов на узле: Nexus считает
их частью репозитория. Проверить занятое:

```sh
kubectl -n nexus exec deploy/nexus -- du -sh /nexus-data/blobs
```

## Обновление

Версия образа меняется в манифесте (тег и дайджест) и приезжает через Flux.
Стратегия `Recreate` означает короткий простой; база и том сохраняются.
Перед мажорным обновлением — сверить путь апгрейда и наличие бэкапа PostgreSQL.

## Удаление

`kubectl delete -k apps/yc/nexus/manifests` уносит под, сервис, маршрут и
`ExternalSecret`, но не namespace и не PVC. Том и база остаются; для полного
удаления — снять PVC и кластер managed-базы (`infra/yc/terraform/nexus`).
