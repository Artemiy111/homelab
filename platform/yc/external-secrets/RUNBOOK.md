# external-secrets: эксплуатация

## Ключ доступа к Lockbox

Создаётся один раз из macOS. Ключ — секрет: не печатать, не коммитить, после
загрузки в кластер удалить файл.

```sh
yc iam key create --service-account-name nexus-lockbox \
  --output /tmp/nexus-lockbox-key.json
kubectl -n external-secrets create secret generic yc-auth \
  --from-file=authorized-key=/tmp/nexus-lockbox-key.json
rm /tmp/nexus-lockbox-key.json
```

## Проверка

```sh
kubectl -n external-secrets get pods
kubectl -n external-secrets get secret yc-auth
flux -n flux-system get helmrelease external-secrets
```

Ожидаемо: три пода в `Running`, HelmRelease в `Ready`, Secret `yc-auth` с ключом
`authorized-key`.

## Ротация ключа

```sh
yc iam key create --service-account-name nexus-lockbox \
  --output /tmp/nexus-lockbox-key.json
kubectl -n external-secrets create secret generic yc-auth \
  --from-file=authorized-key=/tmp/nexus-lockbox-key.json \
  --dry-run=client -o yaml | kubectl apply -f -
rm /tmp/nexus-lockbox-key.json
```

После обновления Secret перезапустить контроллер, чтобы он перечитал ключ:

```sh
kubectl -n external-secrets rollout restart deploy/external-secrets
```

Старый ключ удалить в консоли: `yc iam key list
--service-account-name nexus-lockbox`, затем `yc iam key delete <id>`.

## Диагностика

**`ExternalSecret` в `SecretSyncedError`.** Смотреть
`kubectl -n <namespace> describe externalsecret <имя>`: чаще всего это
`PermissionDenied` (у сервисного аккаунта нет `lockbox.payloadViewer` на секрет)
или истёкший/удалённый ключ в `yc-auth`.

**Секрет не обновляется.** Проверить `refreshInterval` и наличие новой версии:

```sh
yc lockbox payload get <secret-id> --format json | jq -r '.entries[].key'
```

Команда печатает только имена записей; значения не выводить.

## Удаление

`kubectl delete -k platform/yc/external-secrets/releases` уносит оператор и его
CRD. Все `ExternalSecret` в кластере станут нерабочими, а созданные ими Secrets
останутся; удалять оператор, пока им пользуется Nexus, нельзя.
