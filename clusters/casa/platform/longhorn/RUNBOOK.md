# Longhorn: эксплуатация

## Установка

```sh
# 1. Подготовка узла (idempotent; сначала dry-run), с контроллера — macOS
cd infra/ansible
ansible-playbook host.yml --check --diff --ask-become-pass
ansible-playbook host.yml --ask-become-pass

# 2. CSI-снапшоты (CRD + контроллер) — до того, как понадобится первый snapshot
kubectl apply -f clusters/casa/platform/snapshot-controller/app.yaml

# 3. Longhorn
kubectl apply -f clusters/casa/platform/longhorn/app.yaml

# 4. Дождаться, пока Argo докатит релиз
kubectl -n argocd get application longhorn -o wide
kubectl -n longhorn-system get pods --watch

# 5. Классы и снапшот-класс
kubectl apply -f clusters/casa/platform/longhorn/manifests/storageclasses.yaml
kubectl apply -f clusters/casa/platform/longhorn/manifests/volumesnapshotclass.yaml

# 5a. Доступ vmagent к метрикам Longhorn (дополняет чартовую NetworkPolicy)
kubectl apply -f clusters/casa/platform/longhorn/manifests/networkpolicy-metrics.yaml

# 6. Маршрут UI за oauth2-proxy. Argo его не синхронизирует: у Application
# longhorn в spec.sources только чарт и ref: values, файла маршрута там нет.
# После правки в git применять руками, иначе разойдётся с кластером (#858).
kubectl apply -f clusters/casa/platform/longhorn/manifests/route.yaml
```

DNS трогать не нужно: в зоне есть wildcard `*.example.com`.

## Проверка

```sh
# Все компоненты поднялись: manager (DaemonSet), driver-deployer, UI,
# csi-attacher/provisioner/resizer/snapshotter, instance-manager, engine-image
kubectl -n longhorn-system get pods

# Нода и её диск зарегистрированы: Nodes → longhorn-system/node-<hostname>
kubectl -n longhorn-system get nodes.longhorn.io
# Оба условия должны быть True (проверка порогов из values)
kubectl -n longhorn-system get nodes.longhorn.io \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.conditions[?(@.type=="Ready")].status}{" "}{.status.conditions[?(@.type=="Schedulable")].status}{"\n"}{end}'

# default StorageClass в кластере НЕ изменился
kubectl get storageclass

# Тестовый том: RWO
kubectl -n longhorn-test apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-rwo
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
EOF

kubectl -n longhorn-test apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-rwo
spec:
  restartPolicy: Never
  containers:
    - name: c
      image: alpine:3.20
      command: ["sh","-c","echo hello-from-longhorn > /data/hello.txt && cat /data/hello.txt"]
      volumeMounts:
        - { name: v, mountPath: /data }
  volumes:
    - name: v
      persistentVolumeClaim: { claimName: test-rwo }
EOF
kubectl -n longhorn-test logs test-rwo          # hello-from-longhorn

# RWX: класс отдельный не нужен — режим берётся из PVC, а Longhorn отдаёт том
# через share-manager (NFSv4). Два пода монтируют том, второй читает файл первого.
kubectl -n longhorn-test apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-rwx
spec:
  accessModes: [ReadWriteMany]
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
EOF
kubectl -n longhorn-test get pvc test-rwx    # Bound, RWX, рядом поднимается share-manager

# Снапшот: класс обязателен (default — longhorn-snapshot)
kubectl -n longhorn-test apply -f - <<'EOF'
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: test-snap
spec:
  volumeSnapshotClassName: longhorn-snapshot
  source:
    persistentVolumeClaimName: test-rwo
EOF
kubectl -n longhorn-test get volumesnapshot test-snap   # READYTOUSE=true, RESTORESIZE=1Gi
# snapshotHandle выглядит как snap://<longhorn-volume>/snapshot-<uuid>

# Восстановление из снапшота: PVC с dataSource
kubectl -n longhorn-test apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-restore
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: longhorn
  dataSource:
    name: test-snap
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  resources:
    requests:
      storage: 1Gi
EOF
kubectl -n longhorn-test get pvc test-restore    # Bound, данные из снапшота
```

Этот сценарий (запись → RWX → снапшот → восстановление → чтение `hello-from-longhorn`
из восстановленного тома) прогнан на кластере 2026-09-16 целиком.

Убирать тестовое за собой: `kubectl delete ns longhorn-test`, затем Released-PV (`kubectl get pv`),
затем тома в Longhorn (`kubectl -n longhorn-system delete volumes.longhorn.io <name>`) — PV и
Longhorn-том живут отдельно, удаление PV не удаляет том.

UI открывается через authentik; там же видны состояние томов, нод, дисков и бэкапов.

## Возврат тома с `Retain`

### Когда это нужно

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

### Почему нельзя просто `kubectl apply` PVC

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

### Процедура

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

### Что делать с томом после

Том остаётся в состоянии `Released` и занимает место. Удалять стоит только
после того, как восстановленные данные проверены, и это осознанно: это
единственная копия. `longhorn-retain` — это страховка от каскадного удаления,
а не бэкап: он лежит в том же кластере.

### Как удалить том

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

## Грабли, на которые уже наступили

- **StorageClass почти неизменяем.** `reclaimPolicy`, `volumeBindingMode`, `provisioner` и
  `parameters` — immutable ([валидация](https://github.com/kubernetes/kubernetes/blob/v1.36.0/pkg/apis/storage/validation/validation.go)):
  `kubectl patch sc` вернёт `field is immutable`. Значит для смены политики класс надо
  удалить и дать Argo создать его заново (`kubectl delete sc local-path` — существующие PV
  и PVC не страдают). Argo из-за неизменяемого поля будет вечно `OutOfSync` с ошибкой в
  `status.operationState.message`.
- **`VolumeSnapshotClass` без параметра `type` считается бэкапным классом.** Драйвер Longhorn
  для обратной совместимости трактует пустой `type` как `bak` («empty type is considered as
  csiSnapshotTypeLonghornBackup»), после чего падает с `backup target default is not available`.
  Для снапшота нужен `type: snap`; для бэкапа — `type: bak` и настроенный backup target.
  Незавершённый `VolumeSnapshot` при этом трудно удалить: у него и у `VolumeSnapshotContent`
  финалайзеры, которые снимаются вручную.
- **Спека Application живёт в кластере, а не в git.** Argo читает свой `spec` (включая
  `helm.valuesObject`) из объекта в `argocd`, поэтому после правки манифеста в
  `clusters/casa/platform/*/app.yaml` нужно применить его руками — иначе git изменился, а Argo этого не видит.
- **Упавший sync Argo сам не повторяет.** После ошибки контроллер пишет «failed previous sync
  attempt … will not retry» и ждёт нового revision или ручного sync:
  `kubectl -n argocd patch application <name> --type merge -p '{"operation":{"sync":{"prune":true}}}'`
  (`operation` — поле верхнего уровня Application, не в `spec`).
- **`longhorn-static` — не наш класс.** Его создаёт Longhorn (`defaultLonghornStaticStorageClass`)
  для PV, которые вручную привязывают к уже существующим Longhorn-томам. Политика `Delete`.

## Типовые сбои

| Симптом | Причина | Что делать |
|---|---|---|
| Тома в цикле attach/detach | SELinux не даёт `iscsid_t` `dac_override` | `ausearch -m AVC -ts recent`, `semodule -l \| grep local_longhorn`, перезапустить `ansible-playbook host.yml` |
| PVC `Pending` | нет schedulable диска (пороги места, диск выключен, нода недоступна) | Node → Disk в UI, проверить `Available` и `Schedulable` |
| `MountVolume.SetUp failed ... already mounted or mount point busy` | `multipathd` прицепил iSCSI-устройство Longhorn | `systemctl is-active multipathd`; без `/etc/multipath.conf` multipathd по умолчанию блэклистит всё, иначе — blacklist по документации Longhorn |
| UI: ошибка WebSocket handshake | forward-auth мешает upgrade | убрать oauth2-proxy из route и ходить через `kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80` |
| Правки `defaultSettings` в values не применились | Longhorn применяет их при первом создании настройки | менять через UI или `kubectl -n longhorn-system edit settings.longhorn.io <setting>` |
| Argo: Application вечно `OutOfSync` | ресурсы вне git (hooks, jobs) | `preUpgradeChecker.jobEnabled: false` уже выставлен; post-upgrade/uninstall Job Argo видит как свои hooks |
| Том `Released` после удаления PVC | использован класс `longhorn-retain` — так задумано | сначала проверить бэкап, затем удалить PV и том в UI |
| `VolumeSnapshot` висит `readyToUse=false` с `backup target default is not available` | в VolumeSnapshotClass нет `type: snap` — драйвер ушёл в бэкапную ветку | использовать класс `longhorn-snapshot`; у зависшего снапшота снять финалайзеры с `VolumeSnapshot` и `VolumeSnapshotContent` |
| `sc` не меняется: `reclaimPolicy: field is immutable` | поля StorageClass неизменяемы | удалить SC и дать Argo создать заново; при необходимости сделать ручной sync |

Настройки Longhorn (включая backup target и пороги) — это CR `settings.longhorn.io` в
`longhorn-system`, а не ConfigMap чарта: изменение values после установки их не перепишет.

Полезно для наблюдаемости: чарт умеет `ServiceMonitor` (`longhornManager.serviceMonitor.enabled`)
под VictoriaMetrics/vmagent, если понадобятся алерты по диску и томам.

## Удаление

```sh
# 1. Приложения с их ресурсами (иначе финалайзеры подвесят удаление namespace)
kubectl -n argocd delete application longhorn
kubectl -n argocd delete application snapshot-controller
kubectl delete -f clusters/casa/platform/longhorn/manifests

# 2. Данные: удалить PVC/PV (в `longhorn-retain` PV остаётся Released — убирать вручную),
#    тома в UI, потом ноды Longhorn.
#    Для полной зачистки — официальный uninstall-job:
kubectl create -f https://raw.githubusercontent.com/longhorn/longhorn/v1.12.1/uninstall/uninstall.yaml
kubectl -n longhorn-system logs -l job-name=longhorn-uninstall --follow
kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/v1.12.1/uninstall/uninstall.yaml

# 3. Прочее
kubectl delete ns longhorn-system
ls /storage/apps/k8s/longhorn   # каталог данных на узле (удалить вручную)
```

`iscsid` и SELinux-модуль на узле безвредны, когда Longhorn снят.
