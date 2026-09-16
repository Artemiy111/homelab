# Longhorn (CSI-хранилище в k0s)

| | |
|---|---|
| Чарт | `longhorn` 1.12.1 (`https://charts.longhorn.io`) |
| Longhorn | v1.12.1 |
| Namespace | `longhorn-system` |
| UI | https://longhorn.example.com (за oauth2-proxy) |
| Классы | `longhorn` (RWO), `longhorn-rwx` (RWX) — **не default** |
| Реплик на том | 1 (кластер одноузловый) |
| CSI-снапшоты | external-snapshotter v8.6.0 в `kube-system` (6 CRD, включая экспериментальные `groupsnapshot.storage.k8s.io` — так устроен апстримный каталог CRD) |

Что даёт: снапшоты и бэкапы томов, клонирование PVC, расширение, RWX через share-manager,
шифрование, UI и метрики — то есть «взрослый» CSI вместо `local-path-provisioner`.

Чего НЕ делает: не становится StorageClass по умолчанию. `local-path` остаётся default,
Longhorn подключается явным `storageClassName` в PVC. Тома Longhorn живут по своим правилам
(1 реплика, свои пороги по диску), и смешивать их с молчаливым дефолтом не стоит.

## Файлы

| Файл | Что делает |
|---|---|
| `k8s/argocd/longhorn.yaml` | Argo Application: официальный чарт Longhorn |
| `k8s/argocd/snapshot-controller.yaml` | CRD + контроллер CSI-снапшотов (`kube-system`) |
| `k8s/longhorn/storageclasses.yaml` | StorageClass `longhorn` (RWO) и `longhorn-rwx` (RWX) |
| `k8s/longhorn/volumesnapshotclass.yaml` | default `VolumeSnapshotClass` |
| `k8s/traefik/longhorn.ingressroute.yaml` | UI за oauth2-proxy |
| `ansible/host.yml`, `ansible/group_vars/all.yml`, `etc/selinux/local_longhorn.cil` | Подготовка узла: `iscsid`, NFSv4-клиент, каталог данных, SELinux-модуль |

Исследование по теме: [docs/research/k8s/storage-classes-and-csi-provisioners.md](../../docs/research/k8s/storage-classes-and-csi-provisioners.md).

## Почему недостаточно `kubectl apply` чарта

Четыре вещи, каждая из которых ломает Longhorn по-своему:

1. **`iscsid` не запущен.** Пакеты стоят, служба `inactive` — на Fedora это не редкость.
   Без неё iSCSI-тома не подключаются. Плейбук включает и запускает.
2. **SELinux (Fedora/RHEL/Rocky).** `iscsi-initiator-utils` создаёт каталоги в `/var/lib/iscsi`
   без execute-бита, а современный `container-selinux` не даёт `iscsid_t` capability
   `dac_override`. Симптом — все тома в цикле attach/detach. Плейбук ставит минимальный
   CIL-модуль (`etc/selinux/local_longhorn.cil`). Альтернатива — DaemonSet из репозитория
   Longhorn: `deploy/prerequisite/longhorn-iscsi-selinux-workaround.yaml`.
3. **NFSv4-клиент и `kubeletRootDir`.** NFSv4 нужен для RWX и для backup target;
   k0s держит kubelet в `/var/lib/k0s/kubelet`, поэтому в values задан `csi.kubeletRootDir`
   (иначе драйвер монтирует staging-каталоги не туда).
4. **Отдельного диска нет.** Корень — XFS на LVM и ужать его нельзя, поэтому данные Longhorn
   лежат на корневой ФС (`/storage/apps/k8s/longhorn`). Из-за этого в values понижены пороги
   `storageMinimalAvailablePercentage: 10` и `storageReservedPercentageForDefaultDisk: 5`:
   при дефолтных 25/30 при свободных 16% диск сразу стал бы unschedulable.

## Установка

```sh
# 1. Подготовка узла (idempotent; сначала dry-run)
cd /home/artlab/projects/homelab/ansible
ansible-playbook host.yml --check --diff
ansible-playbook host.yml

# 2. CSI-снапшоты (CRD + контроллер) — до того, как понадобится первый snapshot
kubectl apply -f k8s/argocd/snapshot-controller.yaml

# 3. Longhorn
kubectl apply -f k8s/argocd/longhorn.yaml

# 4. Дождаться, пока Argo докатит релиз
kubectl -n argocd get application longhorn -o wide
kubectl -n longhorn-system get pods --watch

# 5. Классы и снапшот-класс
kubectl apply -f k8s/longhorn/storageclasses.yaml
kubectl apply -f k8s/longhorn/volumesnapshotclass.yaml

# 6. UI за oauth2-proxy
kubectl apply -f k8s/traefik/longhorn.ingressroute.yaml
```

DNS трогать не нужно: в зоне есть wildcard `*.example.com`.

## Проверка

```sh
# Все компоненты поднялись: manager (DaemonSet), driver-deployer, UI,
# csi-attacher/provisioner/resizer/snapshotter, instance-manager, engine-image
kubectl -n longhorn-system get pods

# Нода и её диск зарегистрированы: Nodes → longhorn-system/node-<hostname>
kubectl -n longhorn-system get nodes.longhorn.io
# Диск должен быть Schedulable (это и есть проверка порогов из values)
kubectl -n longhorn-system get nodes.longhorn.io -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.diskStatus}{"\n"}{end}'

# default StorageClass в кластере НЕ изменился
kubectl get storageclass

# Тестовый том
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: longhorn-test
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
EOF
kubectl get pvc longhorn-test        # RWO, класс longhorn

kubectl run longhorn-test --image=alpine --restart=Never \
  --overrides='{"spec":{"volumes":[{"name":"v","persistentVolumeClaim":{"claimName":"longhorn-test"}}],"containers":[{"name":"c","image":"alpine","command":["sh","-c","echo ok > /mnt/hello && cat /mnt/hello"],"volumeMounts":[{"name":"v","mountPath":"/mnt"}]}]}}'
kubectl logs longhorn-test           # ok

# CSI-снапшот (нужен шаг 2 из установки)
kubectl apply -f - <<'EOF'
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: longhorn-test
spec:
  volumeSnapshotClassName: longhorn
  source:
    persistentVolumeClaimName: longhorn-test
EOF
kubectl get volumesnapshot longhorn-test   # READYTOUSE=true, RESTORESIZE заполнен
```

UI открывается через authentik; там же видны состояние томов, нод, дисков и бэкапов.

## Ограничения одноузлового Longhorn

- **HA нет.** Реплика одна, узел упал — том недоступен до его возвращения. Документация Longhorn
  рекомендует минимум 3 ноды; здесь Longhorn берётся ради CSI-механик (снапшоты, клоны,
  расширение, RWX, бэкапы) и как подготовка ко второй ноде.
- **`dataLocality: disabled`.** Локальность реплик имеет смысл, когда узлов больше одного.
- **Падение узла = простой.** Спасение — restore из бэкапа, а не текущий том.

## Место на диске (важное ограничение)

Данные Longhorn лежат на корневой ФС вместе с k0s, etcd, образами и `/storage/apps`.
Longhorn — thin provisioning: он *выделяет* больше, чем занимает, и до поры это не заметно.
Заполнение корня означает падение узла, поэтому:

- свободно сейчас ~78 ГБ из 475 ГБ (16%);
- `storageReservedPercentageForDefaultDisk: 5` резервирует ~24 ГБ под систему;
- `storageMinimalAvailablePercentage: 10` требует держать свободными ~47 ГБ,
  то есть Longhorn согласится выделить примерно 30 ГБ томов — и дальше остановится, а не убьёт узел;
- точные числа видны на Node → Disk (`Capacity` / `Available` / `Schedulable`).

Держите объёмы Longhorn-томов небольшими, пока не появится отдельный диск. Когда появится —
перенести каталог данных на его точку монтирования и пересоздать диск в UI.

## Бэкапы

- Снапшот **не** бэкап: цепочка снапшотов живёт внутри тома, сбой тома уносит и её.
  Бэкап — это `backupTarget` в объектном хранилище (S3) или NFS.
- Настроить: Settings → `backup-target` (например, бакет в rustfs) и
  `backup-target-credential-secret`; дальше Recurring Jobs (`snapshot` + `backup`).
- rustfs живёт на этой же ноде: пока она одна, бэкап в него не защищает от потери узла.
  Вторую точку (вторая нода / внешний S3) стоит завести до того, как в Longhorn появится
  что-то реально ценное.

## Когда появится вторая нода

1. Прогнать `ansible/host.yml` на новой ноде (или применить DaemonSet-обходной путь из
   `deploy/prerequisite/longhorn-iscsi-selinux-workaround.yaml`) и открыть порты Longhorn в
   firewalld (`k8s/k0s/firewalld/`) — список портов в Longhorn docs, раздел Networking.
2. В Longhorn появится вторая нода с диском (`defaultDataPath` тот же). Диск — из отдельного
   раздела или диска, не из корня.
3. Поднять `numberOfReplicas: "2"` в `k8s/longhorn/storageclasses.yaml` и применить.
   Существующие тома придётся пересоздать/восстановить: изменить число реплик у живого тома
   можно только в UI (Volume → attach/detach связаны с PVC).
4. Пороги диска (`storageReservedPercentageForDefaultDisk`, `storageMinimalAvailablePercentage`)
   читаются при создании диска; для новой ноды глобальные значения уже подойдут. Менять их
   у существующей ноды — через UI или `kubectl -n longhorn-system edit settings.longhorn.io`.
5. Перевести backup target на внешнюю точку: одно-узловой rustfs перестаёт быть бэкапом.

## Эксплуатация и типовые сбои

| Симптом | Причина | Что делать |
|---|---|---|
| Тома в цикле attach/detach | SELinux не даёт `iscsid_t` `dac_override` | `ausearch -m AVC -ts recent`, `semodule -l \| grep local_longhorn`, перезапустить `ansible-playbook host.yml` |
| PVC `Pending` | нет schedulable диска (пороги места, диск выключен, нода недоступна) | Node → Disk в UI, проверить `Available` и `Schedulable` |
| `MountVolume.SetUp failed ... already mounted or mount point busy` | `multipathd` прицепил iSCSI-устройство Longhorn | `systemctl is-active multipathd`; без `/etc/multipath.conf` multipathd по умолчанию блэклистит всё, иначе — blacklist по документации Longhorn |
| UI: ошибка WebSocket handshake | forward-auth мешает upgrade | убрать oauth2-proxy из route и ходить через `kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80` |
| Правки `defaultSettings` в values не применились | Longhorn применяет их при первом создании настройки | менять через UI или `kubectl -n longhorn-system edit settings.longhorn.io <setting>` |
| Argo: Application вечно `OutOfSync` | ресурсы вне git (hooks, jobs) | `preUpgradeChecker.jobEnabled: false` уже выставлен; post-upgrade/uninstall Job Argo видит как свои hooks |
| Том `Released` после удаления PVC | `reclaimPolicy: Retain` в классах — так задумано | сначала проверить бэкап, затем удалить PV и том в UI |

Настройки Longhorn (включая backup target и пороги) — это CR `settings.longhorn.io` в
`longhorn-system`, а не ConfigMap чарта: изменение values после установки их не перепишет.

Полезно для наблюдаемости: чарт умеет `ServiceMonitor` (`longhornManager.serviceMonitor.enabled`)
под VictoriaMetrics/vmagent, если понадобятся алерты по диску и томам.

## Удаление

```sh
# 1. Приложения с их ресурсами (иначе финалайзеры подвесят удаление namespace)
kubectl -n argocd delete application longhorn
kubectl -n argocd delete application snapshot-controller
kubectl delete -f k8s/longhorn/storageclasses.yaml -f k8s/longhorn/volumesnapshotclass.yaml
kubectl delete -f k8s/traefik/longhorn.ingressroute.yaml

# 2. Данные: удалить PVC/PV (в классах Retain — вручную), тома в UI, потом ноды Longhorn.
#    Для полной зачистки — официальный uninstall-job:
kubectl create -f https://raw.githubusercontent.com/longhorn/longhorn/v1.12.1/uninstall/uninstall.yaml
kubectl -n longhorn-system logs -l job-name=longhorn-uninstall --follow
kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/v1.12.1/uninstall/uninstall.yaml

# 3. Прочее
kubectl delete ns longhorn-system
ls /storage/apps/k8s/longhorn   # каталог данных на узле (удалить вручную)
```

`iscsid` и SELinux-модуль на узле безвредны, когда Longhorn снят.

## Источники

- [Longhorn: Installation Requirements](https://longhorn.io/docs/1.12.1/deploy/install/#installation-requirements)
- [Longhorn: Uninstall](https://longhorn.io/docs/1.12.1/deploy/uninstall/)
- [Longhorn: Enable CSI Snapshot Support](https://longhorn.io/docs/1.12.1/snapshots-and-backups/csi-snapshot-support/enable-csi-snapshot-support/)
- [Longhorn: Storage Class Parameters](https://longhorn.io/docs/1.12.1/references/storage-class-parameters/)
- [Longhorn: Settings](https://longhorn.io/docs/1.12.1/references/settings/)
- [Longhorn: RWX Volumes](https://longhorn.io/docs/1.12.1/nodes-and-volumes/volumes/rwx-volumes/)
- [KB: attach fails due to SELinux denials](https://longhorn.io/kb/troubleshooting-volume-attachment-fails-due-to-selinux-denials/)
- [KB: multipathd на узле](https://longhorn.io/kb/troubleshooting-volume-with-multipath/)
- [KB: default settings do not persist](https://longhorn.io/kb/troubleshooting-default-settings-do-not-persist/)
- [k0s: Storage](https://docs.k0sproject.io/stable/storage/)
