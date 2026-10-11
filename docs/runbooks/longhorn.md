# Longhorn: возврат тома с `Retain`

## Когда это нужно

StorageClass `longhorn-retain` имеет `persistentVolumeReclaimPolicy: Retain`.
Удаление PVC — ручное, удаление namespace, каскадная чистка или переустановка
кластера — такой том **не трогает**: он остаётся в Longhorn в состоянии
`detached`.

Именно так данные uptime-kuma пережили инцидент 0009: PVC исчезла вместе с
namespace, MariaDB была уничтожена, а том с 263 МБ базы остался. Без `Retain
`потеря была бы необратимой.

Отсутствие PVC в кластере **не означает** потерю данных. Проверять надо
хранилище, а не только Kubernetes:

```sh
kubectl -n longhorn-system get volumes.longhorn.io
kubectl -n longhorn-system get volumes.longhorn.io pvc-<uuid> \
  -o jsonpath='{.spec.attach}{" "}{.spec.nodeID}{"\n"}'
```

Пустые `attach` и `nodeID` — том свободен и готов к переподключению.

## Почему нельзя просто `kubectl apply` PVC

PV после удаления claim'а остаётся в фазе `Released` и продолжает ссылаться
на **несуществующий** PVC:

```
$ kubectl get pv pvc-487052ef-… -o jsonpath='{.status.phase} {.spec.claimRef.uid}'
Released 487052ef-2f48-4bee-a0ec-780aad4e80fd
```

Пока `claimRef` на месте, биндер не отдаст PV новому PVC. Созданный с тем же
именем PVC получит **другой** том — как и случилось с `uptime-kuma`: после
пересоздания namespace mariadb-operator заказал свежий том, а старый остался
лежать без дела.

## Процедура

Прежде чем что-то менять, снять и сохранить текущее состояние PV — правку
`claimRef` можно откатить вручную:

```sh
kubectl get pv pvc-<uuid> -o jsonpath='{.spec.claimRef}{"\n"}'
```

Том должен быть свободен. Если `attach` не пуст, сначала отсоединить: иначе
две реплики данных и риск повреждения.

Очистить `claimRef`, чтобы PV снова стал доступен биндеру:

```sh
kubectl patch pv pvc-<uuid> --type=merge -p '{"spec":{"claimRef":null}}'
```

Создать PVC, **привязанный именно к этому PV** — поле `volumeName` здесь
обязательно, иначе provisioner заведёт новый том:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: recover-<что-восстанавливаем>
  namespace: <ns>
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: longhorn-retain
  volumeName: pvc-<uuid>
  resources:
    requests:
      storage: <размер тома>
```

Дождаться `Bound` и проверить, что привязался нужный том:

```sh
kubectl -n <ns> get pvc recover-<что> \
  -o custom-columns='VOLUME:.spec.volumeName,STATUS:.status.phase'
```

Дальше — по содержимому. Для базы данных это выглядит так:

1. Под с образом той же версии БД, монтирование в `/data`,
   `mariadbd --datadir=/data --user=root --socket=/tmp/m.sock
   --skip-networking --skip-grant-tables`.
2. Дамп внутри пода: поток `kubectl exec` рвётся примерно на 30 МБ
   (`websocket: close 1006`), поэтому дамп пишется в файл в поде и
   забирается через `kubectl cp` — с проверкой `md5sum` на обеих сторонах.
3. Импорт в целевую базу. У `mariadb-dump <db>` нет `USE <db>` в выводе,
   поэтому импортировать надо с именем базы: `mariadb -u … <db> < dump.sql`.
4. Перезапустить приложение: если процесс успел прочитать базу до конца
   импорта, он стартует со старым состоянием в памяти.

## Что делать с томом после

Том остаётся в состоянии `Released` и занимает место. Удалять стоит только
после того, как восстановленные данные проверены, и это осознанно: это
единственная копия. `longhorn-retain` — это страховка от каскадного удаления,
а не бэкап: он лежит в том же кластере.

## Как удалить том

Удалять PV недостаточно: при `Retain` удаление PV не трогает данные, и том
останется в Longhorn мёртвым. Удаляются оба объекта, причём удаление тома
Longhorn уводит и PV:

```sh
kubectl -n longhorn-system delete volumes.longhorn.io pvc-<uuid>
kubectl get pv pvc-<uuid>          # обычно уже NotFound
```

Порядок обратный не сработает: PV исчезнет, а том останется занимать место.

Автоматических физических бэкапов MariaDB в кластере нет — см. #937.
Снапшотов etcd тоже нет — см. #599.