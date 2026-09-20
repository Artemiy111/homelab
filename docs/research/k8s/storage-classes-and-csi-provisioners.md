# StorageClass в Kubernetes и CSI-провижионеры: динамическое выделение хранилища

> Sources: официальная документация — kubernetes.io (concepts/storage, reference, blog, deprecation-guide),
> спецификация CSI (github.com/container-storage-interface/spec, v1.13.0), github.com/kubernetes-csi/*
> (external-provisioner, external-snapshotter, external-attacher, external-resizer, csi-driver-nfs,
> csi-driver-smb, docs), kubernetes-sigs/* (nfs-subdir-external-provisioner, aws-ebs-csi-driver,
> sig-storage-local-static-provisioner); доки дистрибутивов — docs.k0sproject.io/stable, docs.k3s.io;
> доки проектов — longhorn.io/docs/1.12.1, github.com/rook/rook + ceph.github.io/ceph-csi, openebs.io/docs,
> github.com/democratic-csi/democratic-csi, github.com/topolvm/topolvm, github.com/openebs/zfs-localpv,
> github.com/juicedata/juicefs-csi-driver, github.com/seaweedfs/seaweedfs-csi-driver,
> github.com/SynologyOpenSource/synology-csi, github.com/NetApp/trident, docs.portworx.com;
> managed Kubernetes — docs.aws.amazon.com/eks, cloud.google.com/kubernetes-engine,
> learn.microsoft.com/azure/aks, docs.digitalocean.com; метрики — GitHub API на 2026-09-16.

Дата исследования: 2026-09-16. Актуальная ветка Kubernetes — **v1.37** (v1.37.0 вышла 2026-08-26);
в этом репозитории k0s — **v1.36.3+k0s.2**, то есть на одну минорную версию позади ветки upstream, что для
мира Storage/CSI несущественно (API `storage.k8s.io/v1` стабилен, CSI-версии совместимы вниз).

Смежные исследования: [k0s-kubernetes-distribution.md](./k0s-kubernetes-distribution.md),
[k0s-setup-guide-vanilla.md](./k0s-setup-guide-vanilla.md),
[cni-solutions.md](./cni-solutions.md),
[../network-filesystem-extension.md](../network-filesystem-extension.md) (NFS/iSCSI/ZFS/SeaweedFS/JuiceFS),
[../docker-registry-selfhosted.md](../docker-registry-selfhosted.md).

---

## 1. Терминология и место в архитектуре

### 1.1. Четыре базовых объекта

Хранилище в Kubernetes описывается связкой из четырёх сущностей ([Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/),
[Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)):

| Объект | Роль | Кто создаёт |
|---|---|---|
| **PersistentVolume (PV)** | Кластерный ресурс, представляющий реальный том (диск, NFS-экспорт, Ceph-образ, локальный каталог) | администратор (static) или провижионер (dynamic) |
| **PersistentVolumeClaim (PVC)** | Заявка пользователя на том: размер, access mode, `storageClassName` | пользователь/приложение |
| **StorageClass** | «Профиль» хранилища: каким драйвером и с какими параметрами создавать тома | администратор / чарт / GitOps |
| **Container Storage Interface (CSI)** | Спецификация, по которой драйвер отдаёт хранилище оркестратору | вендор/проект-драйвер |

PV и PVC связываются один-к-одному через `ClaimRef` — это двусторонняя привязка ([Binding](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#binding)).
Привязка эксклюзивна независимо от способа: «Once bound, PersistentVolumeClaim binds are exclusive,
regardless of how they were bound». После привязки контроллер защиты `kubernetes.io/pvc-protection` /
`kubernetes.io/pv-protection` не даёт удалить PVC/PV, пока они используются подом ([Storage Object in Use Protection](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#storage-object-in-use-protection)).

Access mode задаёт только **сопоставление** PVC↔PV и (для некоторых режимов) ограничение на число подов/узлов;
он **не** enforced на уровне данных: «Volume access modes do **not** enforce write protection once the storage
has been mounted» — гарантию одного пода на весь кластер даёт только `ReadWriteOncePod` ([Access Modes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes)):

| Режим | Сокращение | Смысл |
|---|---|---|
| ReadWriteOnce | RWO | один **узел** (не под!) на запись |
| ReadOnlyMany | ROX | много узлов только на чтение |
| ReadWriteMany | RWX | много узлов на запись (нужен поддерживающий бэкенд: NFS, CephFS, Longhorn share-manager) |
| ReadWriteOncePod | RWOP | один **под** на весь кластер (stable с v1.29, только CSI) |

### 1.2. Static vs dynamic provisioning

- **Static** — администратор заранее создаёт PV, а PVC лишь подбирает подходящий по размеру/классу/режиму
  ([Static](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#static)).
- **Dynamic** — PV создаётся автоматически под конкретный PVC по StorageClass
  ([Dynamic Volume Provisioning](https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/)).
  Для этого на API-сервере должен быть включён admission-контроллер `DefaultStorageClass`
  ([DefaultStorageClass](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#defaultstorageclass)).
- PVC с `storageClassName: ""` **отключает** динамическое выделение для себя и привязывается только к PV
  без класса ([Dynamic](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#dynamic)).

### 1.3. Кто и как вызывает провижионер

Цепочка событий при `kubectl apply` пода с PVC (для внешнего/CSI-провижионера):

1. **kube-apiserver**: admission `DefaultStorageClass` подставляет `storageClassName`, если он не задан.
2. **kube-controller-manager → PersistentVolumeController**: контроллер видит необработанный PVC и помечает его
   аннотацией `volume.kubernetes.io/storage-provisioner` (ранее `volume.beta.kubernetes.io/storage-provisioner`).
   Сам он **не** вызывает CSI-драйвер ([k0s Storage](https://docs.k0sproject.io/stable/storage/);
   [PV Lifecycle](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#lifecycle-of-a-volume-and-claim)).
3. **external-provisioner** (sidecar рядом с CSI-драйвером): библиотека
   [sig-storage-lib-external-provisioner](https://github.com/kubernetes-sigs/sig-storage-lib-external-provisioner)
   следит за PVC с «своим» именем провижионера и вызывает по gRPC CSI `CreateVolume`
   ([external-provisioner](https://kubernetes.io/docs/concepts/storage/storage-classes/#provisioner),
   [csi-provisioner](https://kubernetes-csi.github.io/docs/external-provisioner.html)).
4. Драйвер создаёт том на бэкенде и возвращает `volume_id`; external-provisioner создаёт **PV** в API
   с полями `driver`, `volumeHandle`, `volumeAttributes`.
5. **PersistentVolumeController** связывает PVC↔PV (Binding).
6. При `WaitForFirstConsumer` — **kube-scheduler** выбирает узел с учётом топологии/ёмкости (`CSIStorageCapacity`).
7. **kubelet** на выбранном узле через CSI `NodeStageVolume` + `NodePublishVolume` монтирует том в под.

Итого: StorageClass описывает **что**, CSI-драйвер — **как**, а склейкой занимаются
контроллер в kube-controller-manager и внешние sidecar-процессы. Ключевой момент, который часто удивляет:
**ядро Kubernetes не содержит CSI-драйверов** — их ставит администратор: «The core of Kubernetes does not
install that software for you» ([Migrating to CSI drivers from in-tree plugins](https://kubernetes.io/docs/concepts/storage/volumes/#migrating-to-csi-drivers-from-in-tree-plugins)).

### 1.4. Что было до CSI: in-tree-плагины и CSI migration

Раньше все volume-плагины были **in-tree**: их код жил в репозитории `kubernetes/kubernetes`, компилировался
и поставлялся вместе с бинарниками ядра. Чтобы добавить новое хранилище, нужно было править ядро Kubernetes
([Previously, all volume plugins were "in-tree"](https://kubernetes.io/docs/concepts/storage/volumes/#out-of-tree-volume-plugins)).
Это создавало vendor-lock на релизы K8s и медленные циклы.

**CSI migration** перенаправляет вызовы существующих in-tree-плагинов на соответствующие CSI-драйверы без
изменений в StorageClass/PV/PVC ([CSIMigration](https://kubernetes.io/docs/concepts/storage/volumes/#migrating-to-csi-drivers-from-in-tree-plugins)).
Статус (v1.37) — [Types of Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#types-of-persistent-volumes):

| Плагин | Статус |
|---|---|
| `csi`, `fc`, `hostPath`, `iscsi`, `local`, `nfs` | поддерживаются |
| `awsElasticBlockStore`, `azureDisk` | **удалены** в v1.27 |
| `gcePersistentDisk`, `cinder`, `azureFile`, `vsphereVolume`, `portworxVolume` | deprecated, migration on by default |
| `cephfs`, `rbd` | **недоступны** начиная с v1.31 (ответ: Ceph CSI) |
| `glusterfs` | недоступен с v1.26 |
| `FlexVolume` | deprecated с v1.23, без плана удаления |

CSI migration как механизм — stable с v1.25 ([CSIMigration feature-state](https://kubernetes.io/docs/concepts/storage/volumes/#migrating-to-csi-drivers-from-in-tree-plugins)).
Практический вывод: новые интеграции делаются **только** через CSI; in-tree-типы (`local`, `hostPath`, `nfs`,
`iscsi`) остаются, но не развиваются.

---

## 2. StorageClass как API-объект

### 2.1. Поля

StorageClass — кластерный (не namespace) объект группы `storage.k8s.io/v1`
([StorageClass API reference](https://kubernetes.io/docs/reference/kubernetes-api/config-and-storage-resources/storage-class-v1/),
[StorageClass objects](https://kubernetes.io/docs/concepts/storage/storage-classes/#storageclass-objects)):

| Поле | Назначение | Значение по умолчанию |
|---|---|---|
| `provisioner` | имя volume-плагина/CSI-драйвера; **обязательно** | — |
| `parameters` | произвольные пары ключ/значение для драйвера (≤512 параметров, суммарно ≤256 KiB) | — |
| `reclaimPolicy` | `Delete` или `Retain` для динамически созданных PV | `Delete` |
| `volumeBindingMode` | `Immediate` или `WaitForFirstConsumer` | `Immediate` |
| `allowVolumeExpansion` | разрешить рост тома через правку PVC | `false` |
| `allowedTopologies` | ограничение топологии (зоны/узлы) | — |
| `mountOptions` | опции монтирования (не валидируются; неверная опция ломает mount) | — |

Важные оговорки из официальной доки:

- `mountOptions`: «Mount options are **not** validated on either the class or PV. If a mount option is invalid,
  the PV mount fails» ([Mount options](https://kubernetes.io/docs/concepts/storage/storage-classes/#mount-options)).
- `reclaimPolicy` статически созданных PV класс не меняет — у них остаётся своя политика
  ([Reclaim policy](https://kubernetes.io/docs/concepts/storage/storage-classes/#reclaim-policy)).
- Реальный смысл `parameters` полностью определяется драйвером; ядро их не интерпретирует.

### 2.2. volumeBindingMode — Immediate vs WaitForFirstConsumer

- **Immediate** (дефолт): PV создаётся и привязывается сразу при создании PVC, **без знания** о будущем
  планировании пода. Для топологически-ограниченных бэкендов это даёт unschedulable поды
  ([Volume binding mode](https://kubernetes.io/docs/concepts/storage/storage-classes/#volume-binding-mode)).
- **WaitForFirstConsumer**: привязка/провижионинг откладывается до появления пода; том создаётся с учётом
  resource requests, nodeSelector, affinity/anti-affinity, taints/tolerations
  ([Volume binding mode](https://kubernetes.io/docs/concepts/storage/storage-classes/#volume-binding-mode)).

Ловушка: при `WaitForFirstConsumer` **нельзя** задавать `nodeName` в поде — планировщик обходится, и PVC
навсегда останется `Pending`. Вместо `nodeName` нужно `nodeSelector: kubernetes.io/hostname`
([предупреждение в доке](https://kubernetes.io/docs/concepts/storage/storage-classes/#volume-binding-mode)).
Именно поэтому практически все локальные/топологические драйверы (Longhorn, local-path, TopoLVM,
EBS CSI, GKE `standard-rwo`) используют `WaitForFirstConsumer`.

`allowedTopologies` нужен, только если при `WaitForFirstConsumer` всё равно требуется ограничить зоны
(замена параметров `zone`/`zones`) ([Allowed topologies](https://kubernetes.io/docs/concepts/storage/storage-classes/#allowed-topologies)).

### 2.3. Default StorageClass

- Default-класс помечается аннотацией **`storageclass.kubernetes.io/is-default-class: "true"`**
  ([labels-annotations](https://kubernetes.io/docs/reference/labels-annotations-taints/#storageclass-kubernetes-io-is-default-class)).
- Историческая/legacy-аннотация — `storageclass.beta.kubernetes.io/is-default-class` (до GA). В актуальных
  версиях используется только не-beta вариант; beta-аннотацию в новых кластерах ставить не нужно.
- Если default-классов несколько, для PVC без `storageClassName` берётся **самый новый** default:
  «Kubernetes uses the most recently created default StorageClass»
  ([Default StorageClass](https://kubernetes.io/docs/concepts/storage/storage-classes/#default-storageclass)).
- Кластер может жить **без** default-класса. Тогда PVC создаётся, но `storageClassName` остаётся пустым,
  пока default не появится; после появления default control plane проставит его существующим PVC (кроме тех,
  у которых `storageClassName: ""`) ([Default StorageClass](https://kubernetes.io/docs/concepts/storage/storage-classes/#default-storageclass)).
- «Хотите только один default в кластере» — дока прямо рекомендует не держать несколько
  ([note](https://kubernetes.io/docs/concepts/storage/storage-classes/#default-storageclass)).

### 2.4. Версии API и что удалено

| API | Статус |
|---|---|
| `storage.k8s.io/v1` StorageClass | доступен с v1.6, актуален |
| `storage.k8s.io/v1beta1` StorageClass, CSIDriver, CSINode, VolumeAttachment | **удалён в v1.22** |
| `storage.k8s.io/v1beta1` CSIStorageCapacity | **удалён в v1.27** (v1 — с v1.24) |
| аннотация `volume.beta.kubernetes.io/storage-class` на PVC | deprecated с v1.9, не использовать (есть поле `storageClassName`) |

Источники: [Deprecation guide v1.22](https://kubernetes.io/docs/reference/using-api/deprecation-guide/#storage-resources-v122),
[v1.27](https://kubernetes.io/docs/reference/using-api/deprecation-guide/#csistoragecapacity-v127),
[Using Dynamic Provisioning](https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/#using-dynamic-provisioning).

Смежные API группы: `snapshot.storage.k8s.io/v1` (VolumeSnapshot/Content/Class),
`storage.k8s.io/v1` VolumeAttributesClass. Старый `snapshot.storage.k8s.io/v1beta1` устарел и будет удалён —
storage version переведён на `v1` в external-snapshotter 4.1.0
([CSI Snapshotter README](https://github.com/kubernetes-csi/external-snapshotter)).

---

## 3. CSI в деталях

### 3.1. Спецификация

CSI (Container Storage Interface) — открытая спецификация, владелец — организация
[container-storage-interface/spec](https://github.com/container-storage-interface/spec). Текущая версия —
**v1.13.0** (тег в репозитории; предыдущие мажорные — v1.12, v1.11, v1.10). Спецификация описывает gRPC-интерфейс
между оркестратором (Kubernetes) и плагином хранилища ([spec.md](https://github.com/container-storage-interface/spec/blob/master/spec.md),
[CSI design proposal](https://git.k8s.io/design-proposals-archive/storage/container-storage-interface.md)).

Важно: Kubernetes **не** требует жёстко последнюю версию. Драйвер объявляет свою версию/возможности, а
совместимость проверяется матрицей «минимальная/рекомендуемая CSI ↔ минимальная K8s» в каждом sidecar
(например, external-snapshotter поддерживает CSI ≥ v1.0.0, рекомендует v1.5.0 —
[Compatibility](https://github.com/kubernetes-csi/external-snapshotter#compatibility)).

### 3.2. RPC-вызовы

Спецификация делит вызовы на сервисы ([RPC Interface](https://github.com/container-storage-interface/spec/blob/master/spec.md#rpc-interface)):

**Identity Service** (обязателен каждому плагину):
`GetPluginInfo`, `GetPluginCapabilities`, `Probe`.

**Controller Service** (опционален; включается, если плагин заявляет `CONTROLLER_SERVICE` и/или `VOLUME_ACCESSIBILITY_CONSTRAINTS`):

| RPC | Зачем |
|---|---|
| `CreateVolume` / `DeleteVolume` | динамическое создание/удаление тома |
| `ControllerPublishVolume` / `ControllerUnpublishVolume` | attach/detach тома к узлу (для блочных бэкендов) |
| `ValidateVolumeCapabilities` | проверка поддерживаемых режимов |
| `ListVolumes`, `GetCapacity` | инвентаризация и ёмкость |
| `ControllerGetCapabilities` | набор возможностей |
| `CreateSnapshot`, `DeleteSnapshot`, `ListSnapshots`, `GetSnapshot` | снапшоты |
| `ControllerExpandVolume` | расширение тома |
| `ControllerGetVolume`, `ControllerModifyVolume` | статус и модификация (для VolumeAttributesClass) |
| `ControllerGetVolumeHealth` / `ControllerListVolumeHealth` | health monitoring |

**Node Service** (обязателен на каждом узле):
`NodeStageVolume` / `NodeUnstageVolume`, `NodePublishVolume` / `NodeUnpublishVolume`,
`NodeGetVolumeStats`, `NodeGetCapabilities`, `NodeGetInfo`, плюс `NodeExpandVolume`, health-вызовы.

**Group Controller Service** (снапшоты группы томов): `GroupControllerGetCapabilities`,
`CreateVolumeGroupSnapshot`, `DeleteVolumeGroupSnapshot`, `GetVolumeGroupSnapshot`.

**Snapshot Metadata Service** (Changed Block Tracking): `GetMetadataAllocated`, `GetMetadataDelta`.

### 3.3. Controller vs Node плагины

- **Controller plugin** — централизованный компонент (обычно Deployment), общается с API хранилища:
  создаёт/удаляет тома, снапшоты, расширяет, делает attach (если бэкенд блочный). Может не требоваться —
  для чисто локальных драйверов Controller может отсутствовать
  ([Architecture](https://github.com/container-storage-interface/spec/blob/master/spec.md#architecture)).
- **Node plugin** — DaemonSet на каждом узле, выполняет привилегированные операции на хосте: stage/publish,
  форматирование ФС, монтирование, отдаёт метрики ([Node Service RPC](https://github.com/container-storage-interface/spec/blob/master/spec.md#node-service-rpc)).
- Плагин может поддерживать **только** Node (одноузловые/локальные), только Controller или оба
  ([Plugin capabilities](https://github.com/container-storage-interface/spec/blob/master/spec.md#getplugincapabilities)).

### 3.4. Sidecar-контейнеры

Sidecar'ы — стандартные контейнеры Kubernetes Storage Community, которые снимают с драйвера «Kubernetes-специфику»:
можно обойтись без них, но «highly recommended»
([Sidecar Containers](https://kubernetes-csi.github.io/docs/sidecar-containers.html)):

| Sidecar | Роль | Когда обязателен |
|---|---|---|
| `external-provisioner` | следит за PVC, вызывает `CreateVolume`, создаёт PV | dynamic provisioning |
| `external-attacher` | вызывает `ControllerPublish/UnpublishVolume`, ведёт `VolumeAttachment` | блочные тома, требующие attach |
| `external-resizer` | обрабатывает рост PVC → `ControllerExpandVolume`/`NodeExpandVolume` | `allowVolumeExpansion: true` |
| `external-snapshotter` | `CreateSnapshot`/`DeleteSnapshot`; также группа-снапшоты | snapshots/restore |
| `node-driver-registrar` | регистрирует драйвер в kubelet через plugin registry | всегда на узлах |
| `livenessprobe` | health-check gRPC-эндпоинта драйвера | рекомендуется |
| `external-health-monitor-controller` | сообщает о проблемах томов/узлов через PVC events | health monitoring |
| `cluster-driver-registrar` | **deprecated** | не использовать |

Дополнительно: `snapshot-controller` и `snapshot-validation-webhook` ставит **дистрибутив**, а не драйвер:
«The CRDs and snapshot controller installations are the responsibility of the Kubernetes distribution»
([Volume Snapshots](https://kubernetes.io/docs/concepts/storage/volume-snapshots/#introduction)).
VirtualMachineSnapshot (KubeVirt) и подобные — надстройки над тем же VolumeSnapshot API, а не часть CSI.

---

## 4. Смежные «классы» и объекты вокруг хранилища

### 4.1. VolumeSnapshotClass, VolumeSnapshot, VolumeSnapshotContent

- `VolumeSnapshot`, `VolumeSnapshotContent`, `VolumeSnapshotClass` — это **CRD**, не часть core API; работают
  **только** с CSI ([Volume Snapshots](https://kubernetes.io/docs/concepts/storage/volume-snapshots/)).
- Статус: **GA с v1.20** (feature gate включён по умолчанию и не отключается)
  ([CSI Snapshotter README](https://github.com/kubernetes-csi/external-snapshotter#feature-status),
  [blog GA](https://kubernetes.io/blog/2020/12/10/kubernetes-1-20-volume-snapshot-moves-to-ga/)).
- `VolumeSnapshotClass`: поля `driver`, `deletionPolicy` (`Delete`/`Retain`), `parameters`; default —
  аннотация `snapshot.storage.kubernetes.io/is-default-class: "true"`, по одному default на драйвер
  ([Volume Snapshot Classes](https://kubernetes.io/docs/concepts/storage/volume-snapshot-classes/)).
- Восстановление: PVC с `dataSource.kind: VolumeSnapshot`
  ([Provisioning Volumes from Snapshots](https://kubernetes.io/docs/concepts/storage/volume-snapshots/#provisioning-volumes-from-snapshots)).
- **Group snapshots** (согласованный снапшот нескольких томов) — **alpha** (введён в v1.27, выключен по
  умолчанию, требует CRD `v1beta2` и CSI ≥ v1.10)
  ([CSI Snapshotter README](https://github.com/kubernetes-csi/external-snapshotter#compatibility),
  [blog alpha](https://kubernetes.io/blog/2023/05/08/kubernetes-1-27-volume-group-snapshot-alpha/)).

### 4.2. VolumeAttributesClass

- Мутируемый «класс» хранилища — меняет параметры **существующего** тома (IOPS, throughput) через
  `ControllerModifyVolume`, без пересоздания PVC ([Volume Attributes Classes](https://kubernetes.io/docs/concepts/storage/volume-attributes-classes/)).
- Поля: `driverName`, `parameters`; на PVC — `spec.volumeAttributesClassName`.
- Статус: beta с v1.31, **GA с v1.34** («generally available (GA) as of version 1.34»); с **v1.36 feature gate
  залочен** — отключить уже нельзя (попытка выставить gate игнорируется без ошибки), а появился фича-гейт
  в v1.29 ([Volume Attributes Classes](https://kubernetes.io/docs/concepts/storage/volume-attributes-classes/)).
  Для этого кластера (k0s v1.36.3) значит: `VolumeAttributesClass` доступен, но применим только к драйверам,
  которые реально умеют `ModifyVolume` (у local-path их нет — фича бесполезна).
- Работает только с CSI-драйверами, реализующими `ModifyVolume`; поддержка — в external-provisioner и
  external-resizer. Практический пример — EBS: смена типа/iops/throughput через VolumeAttributesClass
  ([EBS CSI Features](https://github.com/kubernetes-sigs/aws-ebs-csi-driver#features)).

### 4.3. CSIStorageCapacity и планирование по ёмкости

- `CSIStorageCapacity` — объекты, которые создаёт драйвер в своём namespace: ёмкость для класса и узлов,
  имеющих доступ ([Storage Capacity](https://kubernetes.io/docs/concepts/storage/storage-capacity/)).
- Scheduler учитывает ёмкость, если: том ещё не создан, StorageClass ссылается на CSI, включён
  `WaitForFirstConsumer`, а в `CSIDriver` стоит `spec.storageCapacity: true`.
- Статус: **stable с v1.24** ([feature-state stable](https://kubernetes.io/docs/concepts/storage/storage-capacity/)).
- Ограничение: проверка «очень простая» и может опираться на устаревшие данные; при нескольких томах
  возможен вечный `Pending` и ручное вмешательство
  ([Limitations](https://kubernetes.io/docs/concepts/storage/storage-capacity/#limitations)).
- **Важно для homelab:** `local-path-provisioner` ёмкость не отслеживает (у него порой вообще нет Controller),
  поэтому на одном узле практической ценности у этой фичи нет.

### 4.4. Прочие объекты

| Объект | Смысл |
|---|---|
| `CSIDriver` | кластерная регистрация драйвера (attachRequired, podInfoOnMount, fsGroupPolicy, storageCapacity) |
| `CSINode` | per-node список драйверов и их `volume_id`-лимиты |
| `VolumeAttachment` | контроллерная запись «том X приаттачен к узлу Y» (создаёт external-attacher) |

### 4.5. Клонирование PVC и онлайн-расширение

- **Клон**: PVC с `dataSource: {kind: PersistentVolumeClaim, name: ...}`. Требования: только CSI, только
  динамический провижионер, источник в том же namespace, источник должен быть bound и не использоваться,
  `VolumeMode` обязан совпадать; размер — не меньше источника
  ([CSI Volume Cloning](https://kubernetes.io/docs/concepts/storage/volume-pvc-datasource/)).
- **Расширение**: разрешено, только если у StorageClass `allowVolumeExpansion: true`; поддерживается для CSI
  (stable с v1.24). Уменьшать тома нельзя. Расширение ФС возможно для XFS/Ext3/Ext4 и происходит при старте
  пода или онлайн, если ФС это умеет; in-use PVC расширяется без пересоздания пода
  ([Expanding PVCs](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#expanding-persistent-volumes-claims)).
- Провал расширения (например, «слишком большой размер») **ретраится бесконечно**; штатные способы выхода —
  вернуть размер меньше прежнего или вручную снять/пересоздать PVC с `Retain`-политикой
  ([Recovering from Failure](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#recovering-from-failure-when-expanding-volumes)).

---

## 5. Ландшафт провижионеров

### 5.1. Функциональная матрица

Легенда: ✅ да · ⚠️ частично/с оговоркой · ❌ нет · н/д — не применимо. Данные — из официальных доков проектов
(ссылки в подразделах), звёзды/даты — GitHub API на 2026-09-16.

| Решение | Тип | RWX | Снапшоты | Расширение | Клон | Шифрование | Thin-prov. | Репликация |
|---|---|---|---|---|---|---|---|---|
| **local-path-provisioner** | локальный `hostPath`/`local` | ⚠️ только через `sharedFileSystemPath` (NFS) | ❌ | ❌ | ❌ | ❌ | н/д | ❌ |
| **Longhorn** | блочный, распределённый | ✅ (NFS share-manager) | ✅ (+бэкап в S3/NFS) | ✅ | ✅ | ✅ (LUKS2) | ✅ | ✅ (реплики) |
| **Rook + Ceph (RBD)** | блочный, распределённый | ❌ (RBD) / ✅ через CephFS | ✅ | ✅ | ✅ | ✅ (dm-crypt) | ✅ | ✅ |
| **Rook + Ceph (CephFS)** | файловый, распределённый | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **OpenEBS LocalPV-Hostpath** | локальный каталог | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **OpenEBS LocalPV-ZFS** | локальный zvol/dataset | ❌ | ✅ | ✅ | ✅ | ✅ (zfs native) | ✅ | ❌ |
| **OpenEBS LocalPV-LVM** | локальный LV | ❌ | ✅ | ✅ | ✅ | ⚠️ (LUKS) | ✅ | ❌ |
| **OpenEBS Mayastor** | блочный, NVMe-oF | ⚠️ (эксп.) | ✅ | ✅ | ✅ | ⚠️ | ✅ | ✅ |
| **nfs-subdir-external-provisioner** | NFS-каталоги | ✅ | ❌ | ❌ | ❌ | ❌ | н/д | ❌ (сервер) |
| **csi-driver-nfs / nfs-ganesha** | NFS | ✅ | ❌ | ❌ | ❌ | ❌ | н/д | ❌ (сервер) |
| **Synology CSI** | iSCSI/NFS/SMB | ✅ | ✅ | ✅ | ✅ | ⚠️ (DSM) | ✅ | ⚠️ (RAID) |
| **democratic-csi (ZFS)** | iSCSI/NFS/NVMe-oF поверх ZFS | ✅ (NFS) | ✅ | ✅ | ✅ | ⚠️ (ZFS) | ✅ | ⚠️ |
| **TopoLVM** | локальный LVM | ❌ | ✅ (thin) | ✅ | н/д | ❌ | ✅ | ❌ |
| **JuiceFS CSI** | POSIX поверх S3 | ✅ | ⚠️ (метаданные/снапшот-механизмы) | ✅ | ✅ | ⚠️ | ✅ | ✅ (в object store) |
| **SeaweedFS CSI** | файловый поверх SeaweedFS | ✅ | ⚠️ | ⚠️ | ⚠️ | ❌ | ✅ | ✅ |
| **Portworx** | блочный/файловый | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **NetApp Trident** | NFS/iSCSI/NVMe | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### 5.2. Операционная матрица

| Решение | Лицензия | CNCF | Звёзды GitHub | Версия (дата) | Что нужно на узле | Footprint | Годно для 1 узла |
|---|---|---|---|---|---|---|---|
| local-path-provisioner | Apache-2.0 | — (Rancher/SUSE) | 2 940 | v0.0.37 (2026-08-05) | ничего (helper-pod) | ~1 под, десятки MiB | ✅ идеально |
| Longhorn | Apache-2.0 | incubating | 7 984 | v1.12.1 (2026-08-14) | open-iscsi, NFSv4 client, привилегии, /var/lib/longhorn | manager+UI+engine+instance-manager+share-manager | ⚠️ (1 реплика) |
| Rook + Ceph | Apache-2.0 | graduated (Rook) | 13 658 | v1.20.7 (2026-09-02) | OSD-диски, мон/kv | mon+mgr+osd+mds+CSI, гигабайты RAM | ❌ (тяжело) |
| OpenEBS (umbrella) | Apache-2.0 | sandbox | 9 813 | v4.6.1 (2026-09-10) | зависит от движка (LVM/ZFS/hostpath) | от «ничего» (hostpath) до NVMe-oF | ✅ (LocalPV) |
| nfs-subdir-external-provisioner | Apache-2.0 | — (kubernetes-sigs) | 3 045 | последний push 2026-03-31 | внешний NFS-сервер | 1 под | ✅ при наличии NFS |
| csi-driver-nfs | Apache-2.0 | — (kubernetes-csi) | 1 322 | активен (2026-09-15) | внешний NFS | 1 под | ✅ при наличии NFS |
| ceph-csi | Apache-2.0 | — (Ceph/LF) | 1 574 | v3.17.1 (2026-08-24) | Ceph-кластер | — | ❌ |
| democratic-csi | MIT | — | 1 329 | активен (2026-09-14) | ZFS/TrueNAS/ZoL | 1 под | ⚠️ |
| TopoLVM | Apache-2.0 | — | 1 176 | активен (2026-09-16) | LVM2, ядро ≥4.9 | DaemonSet + контроллер | ✅ |
| ZFS LocalPV | Apache-2.0 | sandbox (OpenEBS) | 584 | активен (2026-09-16) | ZFS + ECC RAM реком. | DaemonSet + контроллер | ✅ |
| SeaweedFS CSI | Apache-2.0 | — | 335 | активен (2026-09-15) | SeaweedFS filer | под + DaemonSet | ⚠️ |
| JuiceFS CSI | Apache-2.0 | — | 307 | активен (2026-09-16) | объектное хранилище + движок метаданных (Redis и др.) | DaemonSet + CSI | ⚠️ |
| Synology CSI | Apache-2.0 | — | 706 | v1.4.0 | Synology NAS + DSM 7+ | Deployment + DaemonSet | ⚠️ |
| NetApp Trident | Apache-2.0 | — | 878 | v26.06.1 (2026-08-19) | NetApp ONTAP/AFF | оператор | н/д (корп.) |
| Portworx | проприетарная | — | — | — | dedicated-диски, ядро-модуль | высокий | ❌ |

### 5.3. local-path-provisioner (Rancher/SUSE) — то, что уже стоит

- **Что это:** не-CSI «внешний провижионер», который динамически создаёт `hostPath`- или `local`-тома на узле,
  используя ConfigMap с `config.json`, скриптами `setup`/`teardown` и шаблоном helper-pod
  ([README](https://github.com/rancher/local-path-provisioner)). По сути — упрощение встроенного Local PV:
  «the Kubernetes Local Volume provisioner cannot do dynamic provisioning».
- **Ключевые свойства:** provisioner `rancher.io/local-path`; по умолчанию backend — **hostPath** (меняется на
  `local` аннотацией `volumeType`/`defaultVolumeType`); PV получает `nodeAffinity` по
  `kubernetes.io/hostname` (настраивается параметром `nodeAffinityKey`)
  ([README](https://github.com/rancher/local-path-provisioner)).
- **Чего нет:** лимита ёмкости («No support for the volume capacity limit currently»), снапшотов, клонирования,
  расширения, шифрования, квот, ёмкостного планирования. Это принципиально: `storage: 5Gi` в PVC — просто метка.
- **RWX:** только если задан `sharedFileSystemPath` (общая сетевая ФС на всех узлах) — тогда доступны RWO/ROX/RWX,
  но это уже NFS, а не локальный диск ([README](https://github.com/rancher/local-path-provisioner)).
- **Footprint:** один под в `local-path-storage`; helper-pod запускается лишь на момент mkdir/rm.

**В этом репозитории** (`k8s/argocd/local-path-provisioner.yaml`) стоит чарт `local-path-provisioner`
`v0.0.37` из git-репозитория Rancher (чарт не опубликован в Helm-репо), с `defaultClass: true`,
`nodePathMap: DEFAULT_PATH_FOR_NON_LISTED_NODES → /storage/apps/k8s/local-path` и лимитами
`cpu 1 / memory 256Mi` (requests 50m/64Mi). Класс помечен как **default**, поэтому PVC без `storageClassName`
привязываются к нему. На данных момент это осознанный минимум для одноузлового кластера: k0s, в отличие от k3s,
не содержит провижионера из коробки, и без него PVC висят в `Pending`.

### 5.4. Longhorn (CNCF incubating, Rancher/SUSE)

- **Что это:** распределённое **блочное** хранилище: на каждый том — свой storage controller и синхронные
  реплики на разных узлах, оркеструемые Kubernetes; поверх — NFS share-manager для RWX
  ([README](https://github.com/longhorn/longhorn), [docs](https://longhorn.io/docs/1.12.1/)).
- **Фичи:** снапшоты, бэкапы во внешний S3-совместимый стор или NFS, recurring-джобы, клоны, DR-тома,
  шифрование LUKS2, RWX, автоматический non-disruptive upgrade, UI
  ([README](https://github.com/longhorn/longhorn), [docs](https://longhorn.io/docs/1.12.1/)).
- **Требования:** Kubernetes ≥ v1.25; `open-iscsi`+`iscsid` на узлах для V1-движка; NFSv4-клиент для RWX/бэкапов;
  привилегии root; путь `/var/lib/longhorn`. Для V2-движка (SPDK/NVMe) — ядро ≥6.7, hugepages, модули
  `vfio_pci`/`uio_pci_generic`/`nvme-tcp`, выделенное CPU-ядро ([Install](https://longhorn.io/docs/1.12.1/deploy/install/)).
- **Рекомендации по железу:** «3 nodes, 4 vCPUs, 4 GiB per node», выделенный диск; реплики нельзя раскладывать
  по узлам при одном узле; `default-replica-count` рекомендуется 2 (или 1 для strict-local)
  ([Best Practices](https://longhorn.io/docs/1.12.1/best-practices/)).
- **Подводные камни:** критическая несовместимость с `open-iscsi 2.1.12` на хосте (attach-фейлы)
  ([Install → warning](https://longhorn.io/docs/1.12.1/deploy/install/)); на Fedora с SELinux может понадобиться
  правка политики; «Longhorn can function with HDDs… but latency leads to volume instability» — SSD/NVMe
  рекомендован ([Best Practices](https://longhorn.io/docs/1.12.1/best-practices/)).
- **Одноузловой homelab:** технически ставится, но смысл репликации теряется; остаются снапшоты/бэкапы/RWX/UI
  и «взрослый» CSI-стек — это скорее учебная ценность, чем польза.

### 5.5. Rook + Ceph (CNCF graduated)

- **Что это:** оператор, разворачивающий Ceph (файл/блок/объект) поверх Kubernetes; провайдер Ceph —
  stable ([Rook README](https://github.com/rook/rook)). CSI-драйвер — [ceph-csi](https://github.com/ceph/ceph-csi)
  (RBD + CephFS, v3.17.1). Rook — CNCF **graduated** (2020).
- **Фичи:** RBD (RWO, блочные), CephFS (RWX, файловые), снапшоты, клоны, расширение, шифрование,
  thin-provisioning, репликация — всё «по-взрослому» ([Rook storage docs](https://rook.io/docs/rook/latest/Storage-Configuration/)).
- **Требования:** минимум три мон-узла для нормального quorum, OSD-диски, отдельная RAM/CPU; официальные
  рекомендации Ceph — 512 МБ–1 ГБ RAM минимум на демон, 1–2 ГБ рекомендуемо
  ([Ceph hardware recommendations](https://docs.ceph.com/en/latest/start/hardware-recommendations/),
  см. также [network-filesystem-extension.md](../network-filesystem-extension.md)).
- **Вывод для homelab:** на одном узле Ceph не даёт ни HA, ни смысла; тяжёл и сложен. Хороший учебный проект
  на 3+ узлах, плохой выбор для одноузлового кластера.

### 5.6. OpenEBS (CNCF sandbox)

- **Что это:** зонтичный проект с несколькими движками
  ([OpenEBS README](https://github.com/openebs/openebs), [openebs.io/docs](https://openebs.io/docs)):
  - **LocalPV-Hostpath** (`dynamic-localpv-provisioner`) — замена in-tree hostPath, «zero configuration,
    no CSI driver»;
  - **LocalPV-ZFS** — zvol/dataset поверх ZFS: снапшоты, клоны, resize, шифрование/компрессия ZFS;
  - **LocalPV-LVM** — LVM2-тома;
  - **Mayastor** — реплицированное блочное хранилище на NVMe-oF (multi-node);
  - **RawFile LocalPV** — экспериментальный.
- **Статус:** OpenEBS — CNCF **sandbox**; LocalPV-ZFS/LVM и Mayastor помечены как «Stable, deployable in PROD»
  ([README](https://github.com/openebs/openebs)).
- **Одноузловой homelab:** очень уместен. LocalPV-ZFS/LVM — лёгкий control-plane без dataplane, даёт
  снапшоты/клоны/расширение/квоты поверх одного выделенного диска; Hostpath — прямая замена local-path
  с чуть большей функциональностью.

### 5.7. NFS-based решения

| Решение | Особенности |
|---|---|
| **nfs-subdir-external-provisioner** (kubernetes-sigs) | Динамически создаёт **подкаталоги** `${namespace}-${pvcName}-${pvName}` на уже существующем NFS-сервере; поддерживает `archiveOnDelete`; RWX. Один под. Последний push — 2026-03-31 (проект в поддерживающем режиме) ([README](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner)) |
| **csi-driver-nfs** (kubernetes-csi) | Полноценный CSI-драйвер для NFS; снапшоты **не** поддерживаются (у NFS нет снапшотов на уровне протокола); RWX ([repo](https://github.com/kubernetes-csi/csi-driver-nfs)) |
| **nfs-ganesha-server-and-external-provisioner** | NFS-Ganesha + provisioner в одном; уместен, если NFS-сервер нужно поднять внутри кластера ([repo](https://github.com/kubernetes-sigs/nfs-ganesha-server-and-external-provisioner)) |
| **Synology CSI** | Официальный драйвер: iSCSI + NFS + SMB, thin-provisioned LUN, снапшоты/клоны/расширение, RWX; требует DSM 7+ и хотя бы один storage pool ([README](https://github.com/SynologyOpenSource/synology-csi)) |

NFS в homelab — самый честный способ получить **RWX** (медиа, общие каталоги) без блочного хранилища.
Обратите внимание на оговорки из [network-filesystem-extension.md](../network-filesystem-extension.md):
один TCP-поток на маунт, отсутствие шифрования (кроме Kerberos krb5p), UID-маппинг, «не бэкап».

### 5.8. democratic-csi и TrueNAS/ZFS

- **Что это:** набор CSI-драйверов для iSCSI/NFS/SMB/NVMe-oF поверх ZFS-систем (FreeNAS/TrueNAS, ZoL на Ubuntu),
  плюс локальные `zfs-local-*` драйверы ([README](https://github.com/democratic-csi/democratic-csi)).
- **Возможности:** resize, snapshots, clones — «the current drivers implement the depth and breadth of the csi spec»;
  снапшоты — через external-snapshotter.
- **Когда брать:** если уже есть TrueNAS/ZoL, который должен отдавать хранилище в Kubernetes, и не хочется
  iSCSI «руками». Для homelab без TrueNAS — лишний слой.

### 5.9. TopoLVM, ZFS LocalPV, LVM LocalPV

- **TopoLVM** ([README](https://github.com/topolvm/topolvm)): CSI-плагин на LVM, реализация local PV через LVM;
  поддерживает dynamic provisioning, raw block, topology-aware scheduling, расширение, снапшоты (при thin pool),
  storage capacity tracking. Требует LVM2 на узле и ядро ≥4.9. Не CNCF-проект. Отличный «правильный» вариант
  для одноузлового кластера с выделенным LVM-томом: даёт квоты, снапшоты и топологию без распределённого оверхеда.
- **OpenEBS LocalPV-ZFS** ([README](https://github.com/openebs/zfs-localpv)): control-plane без dataplane поверх
  ядра ZFS; RWO, snapshot/restore/clone/resize, raw block, backup/restore; ZFS RAID и resilience.
  Требует ZFS и (рекомендуется) ECC RAM.
- **OpenEBS LocalPV-LVM**: аналогично, но поверх LVM2.

Все три — локальные (данные на узле, без репликации) и поэтому честно масштабируются только по «ширине» диска,
а не по отказоустойчивости.

### 5.10. JuiceFS CSI и SeaweedFS CSI

- **JuiceFS** ([docs](https://juicefs.com/docs/csi/introduction), [repo](https://github.com/juicedata/juicefs-csi-driver)):
  POSIX-ФС поверх объектного хранилища (S3 и др.) с отдельным движком метаданных (Redis, MySQL, TiKV).
  Даёт RWX, снапшоты (через механизмы метаданных), разделяемый доступ. Требует и объектное хранилище, и БД
  метаданных — заметная операционная нагрузка.
- **SeaweedFS CSI** ([README](https://github.com/seaweedfs/seaweedfs-csi-driver)): static/dynamic provisioning,
  DataLocality, topology; RWX (через filer). Требует работающего кластера SeaweedFS (master + volume + filer);
  SeaweedFS легче Ceph, но всё же кластерная система.

Оба варианта интересны, если в homelab появится объектное хранилище как «источник правды»: они превращают
его в POSIX-тома. В этом репозитории уже есть **rustfs (S3)** — это делает JuiceFS/SeaweedFS потенциально
интересными, но ценой ещё одного движка метаданных/кластера.

### 5.11. Корпоративные драйверы

| Продукт | Модель | Кратко |
|---|---|---|
| **Portworx (Pure Storage)** | проприетарная | Полнофункциональное блочное/файловое хранилище для K8s: репликация, снапшоты, шифрование, ro-кластеры; требует выделенных дисков ([docs.portworx.com](https://docs.portworx.com/)) |
| **NetApp Trident** | Apache-2.0 | Внешний провижионер/CSI для ONTAP/SAN/NAS; снапшоты, клоны, RWX ([github.com/NetApp/trident](https://github.com/NetApp/trident)) |
| **Dell CSM (PowerStore/PowerScale/Unity)** | проприетарная | CSI-драйверы под массивы Dell ([dell/csi-powerstore](https://github.com/dell/csi-powerstore)) |
| **Pure Storage CSI** | проприетарная | CSI для FlashArray/FlashBlade |

Для homelab нерелевантны (нет массивов), но полезно знать: в enterprise именно эти драйверы встречаются
в «сертифицированных» списках платформ.

### 5.12. Облачные драйверы (кратко)

| Облако | Драйвер / класс | Особенности |
|---|---|---|
| **AWS EKS** | EBS CSI (`ebs.csi.aws.com`), EFS CSI, S3 Files; EFS/FSx | EBS — блочный RWO, снапшоты, resize, `VolumeAttributesClass`. В EKS Auto Mode требуется provisioner `ebs.csi.eks.amazonaws.com`, отдельный от стандартного `ebs.csi.aws.com` ([EKS EBS CSI](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html), [EBS CSI features](https://github.com/kubernetes-sigs/aws-ebs-csi-driver#features)) |
| **GKE** | PD CSI `pd.csi.storage.gke.io`; Filestore CSI (RWX) | Дефолтный класс — `standard-rwo` (balanced PD), `premium-rwo` (SSD PD); в `standard-rwo` `volumeBindingMode: WaitForFirstConsumer` ([GKE PD CSI](https://cloud.google.com/kubernetes-engine/docs/how-to/persistent-volumes/gce-pd-csi-driver)) |
| **AKS** | Azure Disk CSI, Azure Files CSI | Дефолтный класс **`managed-csi`** = Standard SSD; `managed-csi-premium` = Premium SSD; с AKS 1.35 — `managed-csi-premium-v2` ([AKS disk CSI](https://learn.microsoft.com/en-us/azure/aks/azure-csi-disk-storage-provision)) |
| **DigitalOcean DOKS** | `do-block-storage` | RWO; RWX — через NFS-shares DigitalOcean, ROX не поддерживается ([DO volumes](https://docs.digitalocean.com/products/kubernetes/how-to/add-volumes/)) |
| **Hetzner** | `hcloud-csi` (`hcloud-volumes`) | Только **RWO**; требует K8s ≥1.19 ([hcloud-csi](https://github.com/hetznercloud/csi-driver)) |
| **Civo** | Civo volume | Вторичные данные о `civo-volume`; официальную страницу проверить не удалось — **не подтверждено** |

### 5.13. `local` static PV — самый простой вариант

Встроенный тип `local` — это PV, указывающий на конкретный путь/устройство с обязательной `nodeAffinity`.
Динамического провижионинга у него нет, но StorageClass всё равно создают, чтобы включить
`WaitForFirstConsumer` ([Local](https://kubernetes.io/docs/concepts/storage/storage-classes/#local)).
Автоматизировать создание PV из заранее разбитых «слотов» можно
[sig-storage-local-static-provisioner](https://github.com/kubernetes-sigs/sig-storage-local-static-provisioner).
Это «дешёвый» и предсказуемый вариант, если нужен полный контроль и не нужны снапшоты/расширение.

---

## 6. Популярность и реальное использование

### 6.1. Что можно измерить (факты)

Активность репозиториев — GitHub API на 2026-09-16 (звёзды меняются ежедневно):

| Проект | ⭐ | Последний push |
|---|---|---|
| rook/rook | 13 658 | 2026-09-16 |
| openebs/openebs | 9 813 | 2026-09-16 |
| longhorn/longhorn | 7 984 | 2026-09-16 |
| kubernetes-sigs/nfs-subdir-external-provisioner | 3 045 | 2026-03-31 |
| rancher/local-path-provisioner | 2 940 | 2026-09-16 |
| ceph/ceph-csi | 1 574 | 2026-09-16 |
| container-storage-interface/spec | 1 489 | 2026-09-02 |
| democratic-csi/democratic-csi | 1 329 | 2026-09-14 |
| kubernetes-csi/csi-driver-nfs | 1 322 | 2026-09-15 |
| topolvm/topolvm | 1 176 | 2026-09-16 |
| NetApp/trident | 878 | 2026-09-15 |
| hetznercloud/csi-driver | 798 | 2026-09-15 |
| SynologyOpenSource/synology-csi | 706 | 2026-09-15 |
| kubernetes-csi/external-snapshotter | 644 | 2026-09-14 |
| openebs/zfs-localpv | 584 | 2026-09-16 |
| kubernetes-csi/external-provisioner | 419 | 2026-09-14 |
| seaweedfs/seaweedfs-csi-driver | 335 | 2026-09-15 |
| juicedata/juicefs-csi-driver | 307 | 2026-09-16 |
| ctrox/csi-s3 | 828 | **архивирован 2025-04-17** |

Наблюдение: `nfs-subdir-external-provisioner` фактически в поддерживающем режиме (нет push с марта 2026),
`csi-s3` архивирован — для S3-бэкендов смотрите на JuiceFS/SeaweedFS.

### 6.2. CNCF и отраслевые данные

- **Статусы CNCF (факт):** Rook — **graduated**; Longhorn — **incubating**; OpenEBS — **sandbox**;
  Ceph (и ceph-csi) — проект Linux Foundation, **не** CNCF; TopoLVM, democratic-csi, JuiceFS, SeaweedFS CSI,
  Synology CSI, Trident — не CNCF-проекты
  ([CNCF projects](https://www.cncf.io/projects/), README проектов).
- **Опросы:** CNCF Annual Survey **не разбивает** респондентов по storage-решениям — на странице отчёта
  релевантной разбивки нет ([CNCF Annual Survey 2024](https://www.cncf.io/reports/cncf-annual-survey-2024/)).
  Поэтому любые «проценты рынка» по провижионерам — **вторичные/субъективные оценки**, а не факт.
- **Adopters (факт, но вендорский):** Rook — CNCF graduated и используется в Ceph-сообществах; Longhorn идёт
  в Rancher/Harvester; AWS поддерживает собственные CSI-драйверы; managed-платформы поставляют «свой»
  драйвер по умолчанию (см. 5.12).

### 6.3. Что выбирают по умолчанию в managed Kubernetes (факт)

- EKS — EBS CSI (блочный RWO) + EFS CSI для RWX.
- GKE — PD CSI (`standard-rwo` по умолчанию, Filestore для RWX).
- AKS — Azure Disk CSI (`managed-csi` по умолчанию) + Azure Files для RWX.
- DO — `do-block-storage`; Hetzner — `hcloud-volumes`.

Общий паттерн: «один блочный драйвер по умолчанию (RWO) + отдельный сетевой (RWX)». Это ровно то,
что дублируют локальные альтернативы (local-path + NFS).

### 6.4. Что чаще встречается в самохостинге/homelab (оценка — субъективно)

Прямых опросов нет; ниже — **субъективная** оценка на основе официальных доков, README и распространённости
в гайдах для k3s/k0s/Rancher (не статистика):

1. `local-path-provisioner` — дефолт в k3s/Rancher Desktop и самый частый выбор в одноузловых кластерах.
2. Longhorn — популярнейший «распределённый» выбор в Rancher-мире (UI, бэкапы, снапшоты).
3. OpenEBS LocalPV (Hostpath/ZFS/LVM) и TopoLVM — для тех, кто хочет квоты/снапшоты поверх локального диска.
4. `nfs-subdir` / `csi-driver-nfs` — когда нужен RWX и есть NAS/NFS.
5. Rook/Ceph — «взрослый» homelab на 3+ узлах; на одном узле почти не встречается.

---

## 7. Практика и эксплуатация

### 7.1. Проверить default-класс

```bash
kubectl get storageclass
# или точнее — сама аннотация:
kubectl get sc -o custom-columns=\
NAME:.metadata.name,DEFAULT:.metadata.annotations.storageclass\\.kubernetes\\.io/is-default-class,PROV:.provisioner,BIND:.volumeBindingMode
```

Удаление/смена default и «сделать класс не-default» описаны в
[Change the default StorageClass](https://kubernetes.io/docs/tasks/administer-cluster/change-default-storage-class/).

### 7.2. Типовой симптом: PVC `Pending` из-за `WaitForFirstConsumer`

`Pending` у PVC при `WaitForFirstConsumer` — **нормально**, пока не появился под: том не создаётся раньше
планирования. Смотрите `kubectl describe pvc <name>` — событие обычно гласит
`waiting for first consumer to be created before binding`. Причины, почему это «залипает»:

- под не может быть запланирован (нет ресурсов, taints, nodeSelector без подходящего узла);
- в поде задан `nodeName` вместо `nodeSelector: kubernetes.io/hostname` — планировщик обходится, PVC `Pending`
  ([Volume binding mode](https://kubernetes.io/docs/concepts/storage/storage-classes/#volume-binding-mode));
- `WaitForFirstConsumer` не поддержан драйвером.

### 7.3. Диагностика `volume not found` / `failed to provision`

Порядок разбора (все — по контроллерам/событиям):

1. `kubectl describe pvc` и `kubectl get events -A --sort-by=.lastTimestamp` — первичные сообщения.
2. Контроллер-менеджер: `PersistentVolumeController` пишет события вида `failed to provision volume with
   StorageClass`; смотрите логи `kube-controller-manager` (в k0s — `journalctl -u k0s`).
3. Sidecar-логи драйвера: `kubectl logs -n <driver-ns> <csi-provisioner-pod> -c csi-provisioner`.
4. `kubectl get pv`, `kubectl get volumeattachment`, проверка `driver`/`volumeHandle` в PV.
5. Ошибки узла: `kubectl logs -n <driver-ns> <node-pod> -c csi-plugin` + `journalctl -u kubelet`.

Самая частая причина в k0s-классе NO-дистрибутивов — **драйвера просто нет** (k0s не поставляет провижионер),
и PVC навсегда в `Pending`/`volume not found`.

### 7.4. Retention при удалении

- `Delete` (дефолт): удаление PVC удаляет и PV, и реальный том
  ([Delete](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#delete)).
- `Retain`: PV остаётся в `Released`, данные целы; ручные шаги — удалить PV, вычистить и удалить том на бэкенде
  ([Retain](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#retain)).
- Сменить политику можно у живого PV:
  [Change the Reclaim Policy of a PersistentVolume](https://kubernetes.io/docs/tasks/administer-cluster/change-pv-reclaim-policy/).
- Практика homelab: для всего, что жалко, ставьте `Retain` на StorageClass (или хотя бы на важные PVC) —
  это спасение от «удалил PVC по ошибке». В `local-path` и большинстве примеров по умолчанию `Delete`.

### 7.5. Миграция между классами

У StorageClass **нельзя** просто поменять у существующего PVC. Реальный путь:

1. Создать новый PVC нужного класса (можно чуть больше размером).
2. Остановить потребителя, скопировать данные (`kubectl exec`, `rsync`, снапшот-клонирование).
3. Переключить под/деплой на новый PVC, проверить, удалить старый.

Если драйвер поддерживает **клоны**, шаг 2-3 быстрее: PVC с `dataSource` на старый PVC
([CSI Volume Cloning](https://kubernetes.io/docs/concepts/storage/volume-pvc-datasource/)).
Клон можно делать между разными классами (класс назначения может отличаться). Снапшот-восстановление
в новый класс — тоже легальный путь.

### 7.6. Лимиты и квоты

- На стороне ядра лимит — `ResourceQuota` на `requests.storage` в namespace (считает запрошенные размеры PVC).
- **Реальные** ограничения (максимальная ёмкость, максимальный IOPS, тонкость провижионинга) задаёт драйвер.
  У `local-path-provisioner` лимита ёмкости нет — `storage: 5Gi` ничего не гарантирует и не ограничивает.
- `CSIStorageCapacity` помогает планировщику, но не заменяет квоты.

### 7.7. Безопасность и шифрование

- **Шифрование at rest:** зависит от драйвера. Longhorn — LUKS2; ZFS — нативно; RBD — dm-crypt; облака —
  свои ключи. `hostPath`/`local` — без шифрования.
- **Секреты для драйвера:** StorageClass `parameters` могут ссылаться на Secret
  (`csi.storage.k8s.io/provisioner-secret-name`/`-namespace`), а PV — через `controllerPublishSecretRef`,
  `nodeStageSecretRef`, `nodePublishSecretRef`, `nodeExpandSecretRef`
  ([CSI volumes fields](https://kubernetes.io/docs/concepts/storage/volumes/#csi)).
- **Pod Security:** CSI node-плагины привилегированны и монтируют host-пути — это принято, но именно поэтому
  нужно доверять драйверу. Longhorn, в частности, требует root/privileged и монтирует `/dev`, `/proc`, `/sys`
  ([Install → Root and Privileged Permission](https://longhorn.io/docs/1.12.1/deploy/install/)).
- Не храните пароли/ключи в `parameters` StorageClass — они видны всем, кто может читать классы.

### 7.8. Бэкапы PV и почему снапшоты ≠ бэкап

Инструменты:

| Инструмент | Что делает |
|---|---|
| **Velero** | Бэкап/restore Kubernetes-ресурсов + томов (CSI snapshots, file-system backup через Restic/Kopia) |
| **restic / kopia** | Файловые бэкапы содержимого томов во внешнее хранилище |
| **k8up** | Оператор Restic-бэкапов для K8s (namespaced, с расписаниями) |
| **VolumeSnapshot (CSI)** | «Мгновенный» снапшот тома на бэкенде |
| **Longhorn backup / Rook/Trident** | Встроенные механизмы отправки снапшотов во внешний S3/NFS |

Почему снапшот **не** бэкап:

1. Снапшот обычно живёт в **той же** системе/аккаунте, что и оригинал: сбой, шифрование-вымогатель или
   ошибка оператора уносит и оригинал, и снапшоты.
2. Снапшот привязан к драйверу/кластеру: восстановить в другой кластер/вендора часто нельзя.
3. Снапшот не даёт версионирования приложения (БД согласована лишь настолько, насколько согласован снапшот).
4. У `local-path-provisioner` снапшотов нет вообще — только файловый бэкап (restic) или rsync.

Правильная схема: **snapshot — для быстрого rollback, backup во внешнее хранилище (S3/rustfs или удалённый
NFS) — для восстановления.** В этом репозитории роль внешнего хранилища играет rustfs (S3).

---

## 8. Рекомендации под этот homelab

### 8.1. Текущее состояние

- Один узел, k0s **v1.36.3+k0s.2**; k0s не поставляет провижионер по умолчанию — «Follow your storage driver's
  installation instructions» ([k0s Storage](https://docs.k0sproject.io/stable/storage/)).
- Поставлен `local-path-provisioner v0.0.37` через Argo CD, класс **default**, данные в
  `/storage/apps/k8s/local-path` (быстрый локальный диск), лимиты 1 CPU/256Mi.
- Есть rustfs (S3); GitOps — Argo CD.
- k3s (для сравнения) включает `local-path-provisioner` из коробки ([k3s storage](https://docs.k3s.io/storage)).

### 8.2. `/storage/apps` и `hostPath` vs local PV — важное различие

`hostPath` — это **не** то же самое, что local PV:

| | `hostPath` | `local` PV |
|---|---|---|
| node affinity | нет в спецификации; планировщик не знает о привязке | обязательна, планировщик учитывает |
| Поведение при переезде пода | под может уехать на другой узел и не найти данные | под ставится на нужный узел (с WaitForFirstConsumer) |
| Безопасность | даёт поду доступ к ФС хоста (риск) | путь тома ограничен |
| Документация | «for single node testing only; WILL NOT WORK in a multi-node cluster» ([Types of PV](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#types-of-persistent-volumes)) | рекомендованный способ локального хранилища |

Нюанс: `local-path-provisioner` по умолчанию создаёт именно `hostPath`-PV, но **добавляет** `nodeAffinity`
по `kubernetes.io/hostname` — то есть ведёт себя как local PV и на одном узле это работает. Если узел один,
разница hostPath/local почти неощутима; при появлении второй ноды это станет критично — тогда переходите на
`volumeType: local` (аннотация) или на драйвер, который делает `local`-PV (TopoLVM/OpenEBS).

Практика для `/storage/apps`: держите **весь** stateful в одном хорошо известном каталоге, не создавайте
произвольные `hostPath` в манифестах приложений (это ломает переносимость и бэкапы), и делайте
файловый бэкап этого каталога (restic) — это единственная реальная страховка при `local-path`.

### 8.3. Реалистичные сценарии

| Сценарий | Плюсы | Минусы | Ресурсы | Риск |
|---|---|---|---|---|
| **A. Оставить local-path** | Ноль оверхеда, уже работает, GitOps, быстрый локальный диск | Нет снапшотов/квот/расширения/RWX; ёмкость не enforced; данные привязаны к узлу | ~1 под, десятки MiB | Средний: нет защиты от ошибок удаления |
| **B. NFS (nfs-subdir/csi-driver-nfs)** | RWX, общий доступ, простой | Зависимость от NFS-сервера; нет снапшотов; производительность сети | 1 под | Средний |
| **C. OpenEBS LocalPV-ZFS или TopoLVM** | Снапшоты, клоны, resize, квоты; лёгкий control-plane; хорошо для 1 узла | Нужен выделенный диск/раздел и LVM/ZFS; данные всё ещё на узле | DaemonSet + контроллер | Низкий-средний |
| **D. Longhorn (1 реплика)** | CSI «по-взрослому»: снапшоты, бэкапы в S3/NFS, RWX, UI, шифрование | Тяжёлый для 1 узла; требует open-iscsi/NFS/привилегий; репликация бессмысленна | Manager/UI/engine/share-manager, сотни MiB+ | Средний |
| **E. Rook + Ceph (1 узел)** | Полный Ceph: RBD/CephFS, снапшоты, репликация | На одном узле не даёт HA; тяжёл и сложен; много демонов и RAM | Гигабайты RAM | Высокий |
| **F. JuiceFS/SeaweedFS CSI поверх rustfs** | RWX + POSIX поверх уже имеющегося S3; масштабируемость | Нужен движок метаданных (Redis) / кластер SeaweedFS; сложнее | +Redis/SeaweedFS | Средний-высокий |

### 8.4. Рекомендация

**Краткосрочно — оставить `local-path-provisioner`** (сценарий A), но закрыть его слабые места:

1. **`reclaimPolicy: Retain`** для класса, который хранит важные данные, — иначе `kubectl delete pvc`
   необратимо уносит данные.
2. **Файловый бэкап** `/storage/apps` во внешнее хранилище (rustfs/S3) — обязателен, потому что
   снапшотов у local-path нет.
3. **Никаких ad-hoc `hostPath`** в манифестах: только PVC → local-path.

**При появлении реальной потребности** в снапшотах/клонах/квотах/расширении — переходить не на Longhorn
(избыточен для одного узла), а на **сценарий C**: выделенный раздел/LVM-том + **TopoLVM** или
**OpenEBS LocalPV-LVM/ZFS**. Это даёт прод-навыки (CSI, thin provisioning, снапшоты, квоты) без
распределённого оверхеда. Тогда данные логично перенести с `local-path` на новый класс через клон/копию.

**Longhorn (D)** стоит включить как учебный проект — но осознанно: с `default-replica-count: 1`
и пониманием, что репликация на одном узле не защищает. Это лучший способ потрогать «настоящий»
распределённый CSI + бэкапы в S3/NFS. Держать его как **не**-default рядом с local-path.

**Rook/Ceph (E)** — только когда будет 3+ узла; на одном узле это дорого и бессмысленно.

**NFS (B)** — если появится потребность в RWX (медиа, общие каталоги) и внешний NFS-сервер (например,
диск ноутбука из [network-filesystem-extension.md](../network-filesystem-extension.md)). Помните: NFS-том —
не бэкап и не HA.

### 8.5. Чек-лист перед сменой провижионера

- [ ] Есть ли реальная потребность (снапшоты/RWX/квоты/расширение) — или это «на всякий случай»?
- [ ] Готовы ли системные зависимости: `open-iscsi` (Longhorn V1), NFSv4-клиент (Longhorn RWX/backup),
      LVM2/ZFS (TopoLVM/OpenEBS), ядро ≥6.7 и hugepages (Longhorn V2)?
- [ ] Учтён ли k0s-специфичный `kubelet root dir` (`/var/lib/k0s/kubelet`) в манифестах CSI-драйвера?
      k0s явно предупреждает, что CSI-плагины могут монтировать этот каталог и требуют корректировки
      ([k0s Storage](https://docs.k0sproject.io/stable/storage/)).
- [ ] Не станет ли новый класс **default** случайно (одновременно два default = непредсказуемость)?
- [ ] Настроен ли `Retain` там, где нужно, и есть ли внешний бэкап (rustfs)?
- [ ] Понятен ли план восстановления в случае потери узла (для локальных драйверов — только бэкап)?

---

## Не подтверждённые утверждения / оговорки

- **«Доли рынка» провижионеров** — не подтверждены: CNCF Annual Survey не публикует разбивку по storage
  решениям; любые проценты из вторичных обзоров не проверялись.
- **Civo default StorageClass** — официальная страница про volumes отдала 404 на момент исследования;
  название класса `civo-volume` не подтверждено первоисточником.
- **AWS EKS default StorageClass (`gp2`/`gp3`)** — прямо в проверенных официальных страницах не зафиксирован;
  подтверждено лишь, что EBS CSI — стандартный драйвер и что в EKS Auto Mode требуется
  `ebs.csi.eks.amazonaws.com`. Рекомендацию «использовать gp3» стоит сверить перед внедрением.
- **Популярность в homelab (раздел 6.4)** — субъективная оценка, не статистика.
- **Точные числа звёзд и даты** — GitHub API на 2026-09-16; меняются ежедневно.
- **JuiceFS CSI: снапшоты/версионирование** — детали зависят от движка метаданных и версии; в матрице
  помечено как ⚠️, точный перечень стоит сверить в актуальной документации JuiceFS.
- **SeaweedFS CSI: снапшоты/расширение** — поддержка помечена как ⚠️ (нужна проверка по версии драйвера).
- **Точные версии облачных CSI-драйверов** (не SDK-репозиториев) не сверялись; в таблице — только факты,
  взятые со страниц managed-сервисов.

---

## Источники

**Kubernetes core:**
- Storage Classes: https://kubernetes.io/docs/concepts/storage/storage-classes/
- Persistent Volumes: https://kubernetes.io/docs/concepts/storage/persistent-volumes/
- Dynamic Volume Provisioning: https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/
- Volumes (CSI, CSI migration): https://kubernetes.io/docs/concepts/storage/volumes/
- Volume Snapshots: https://kubernetes.io/docs/concepts/storage/volume-snapshots/
- Volume Snapshot Classes: https://kubernetes.io/docs/concepts/storage/volume-snapshot-classes/
- Volume Attributes Classes: https://kubernetes.io/docs/concepts/storage/volume-attributes-classes/
- CSI Volume Cloning: https://kubernetes.io/docs/concepts/storage/volume-pvc-datasource/
- Storage Capacity: https://kubernetes.io/docs/concepts/storage/storage-capacity/
- StorageClass API reference: https://kubernetes.io/docs/reference/kubernetes-api/config-and-storage-resources/storage-class-v1/
- is-default-class annotation: https://kubernetes.io/docs/reference/labels-annotations-taints/#storageclass-kubernetes-io-is-default-class
- Change the default StorageClass: https://kubernetes.io/docs/tasks/administer-cluster/change-default-storage-class/
- Change the reclaim policy: https://kubernetes.io/docs/tasks/administer-cluster/change-pv-reclaim-policy/
- Deprecation guide: https://kubernetes.io/docs/reference/using-api/deprecation-guide/
- Releases / версии: https://kubernetes.io/releases/
- Blog: Volume Snapshot GA: https://kubernetes.io/blog/2020/12/10/kubernetes-1-20-volume-snapshot-moves-to-ga/
- Blog: Volume Group Snapshot alpha: https://kubernetes.io/blog/2023/05/08/kubernetes-1-27-volume-group-snapshot-alpha/
- Blog: CSI migration beta: https://kubernetes.io/blog/2019/12/09/kubernetes-1-17-feature-csi-migration-beta/

**CSI:**
- Спецификация: https://github.com/container-storage-interface/spec/blob/master/spec.md (v1.13.0)
- CSI design proposal: https://git.k8s.io/design-proposals-archive/storage/container-storage-interface.md
- kubernetes-csi docs: https://kubernetes-csi.github.io/docs/
- Sidecar-контейнеры: https://kubernetes-csi.github.io/docs/sidecar-containers.html
- external-provisioner: https://github.com/kubernetes-csi/external-provisioner
- external-snapshotter: https://github.com/kubernetes-csi/external-snapshotter
- external-attacher: https://github.com/kubernetes-csi/external-attacher
- external-resizer: https://github.com/kubernetes-csi/external-resizer
- sig-storage-lib-external-provisioner: https://github.com/kubernetes-sigs/sig-storage-lib-external-provisioner

**Дистрибутивы:**
- k0s Storage (CSI): https://docs.k0sproject.io/stable/storage/
- k3s Storage: https://docs.k3s.io/storage

**Провижионеры:**
- local-path-provisioner: https://github.com/rancher/local-path-provisioner
- Longhorn: https://github.com/longhorn/longhorn · https://longhorn.io/docs/1.12.1/deploy/install/ · https://longhorn.io/docs/1.12.1/best-practices/
- Rook: https://github.com/rook/rook · https://rook.io/docs/rook/latest/Storage-Configuration/
- Ceph CSI: https://github.com/ceph/ceph-csi
- OpenEBS: https://github.com/openebs/openebs · https://openebs.io/docs
- Mayastor: https://github.com/openebs/mayastor
- zfs-localpv: https://github.com/openebs/zfs-localpv
- TopoLVM: https://github.com/topolvm/topolvm
- NFS subdir external provisioner: https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner
- csi-driver-nfs: https://github.com/kubernetes-csi/csi-driver-nfs
- NFS Ganesha server + provisioner: https://github.com/kubernetes-sigs/nfs-ganesha-server-and-external-provisioner
- democratic-csi: https://github.com/democratic-csi/democratic-csi
- JuiceFS CSI: https://juicefs.com/docs/csi/introduction · https://github.com/juicedata/juicefs-csi-driver
- SeaweedFS CSI: https://github.com/seaweedfs/seaweedfs-csi-driver
- Synology CSI: https://github.com/SynologyOpenSource/synology-csi
- NetApp Trident: https://github.com/NetApp/trident
- Portworx: https://docs.portworx.com/
- Dell CSI PowerStore: https://github.com/dell/csi-powerstore
- sig-storage-local-static-provisioner: https://github.com/kubernetes-sigs/sig-storage-local-static-provisioner

**Managed Kubernetes:**
- EKS EBS CSI: https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html · EBS CSI features: https://github.com/kubernetes-sigs/aws-ebs-csi-driver
- GKE PD CSI: https://cloud.google.com/kubernetes-engine/docs/how-to/persistent-volumes/gce-pd-csi-driver
- AKS Azure Disk CSI: https://learn.microsoft.com/en-us/azure/aks/azure-csi-disk-storage-provision
- DigitalOcean Volumes: https://docs.digitalocean.com/products/kubernetes/how-to/add-volumes/
- Hetzner CSI: https://github.com/hetznercloud/csi-driver

**CNCF:**
- Проекты и статусы: https://www.cncf.io/projects/
- Rook graduation: https://www.cncf.io/announcements/2020/10/07/cloud-native-computing-foundation-announces-rook-graduation/
- CNCF Annual Survey 2024: https://www.cncf.io/reports/cncf-annual-survey-2024/
