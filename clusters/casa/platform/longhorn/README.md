# Longhorn (CSI-хранилище в k0s)

| | |
|---|---|
| UI | https://longhorn.example.com (за oauth2-proxy) |
| Классы | `longhorn` (Delete) и `longhorn-retain` (Retain) — **не default**; плюс `longhorn-static` (создаёт сам Longhorn для PV существующих томов, `Delete`) |
| Реплик на том | 1 (кластер одноузловый) |
| Снапшоты | VolumeSnapshotClass `longhorn-snapshot` (default, `type: snap`) и `longhorn-backup` (`type: bak`, нужен backup target) |
| CSI-снапшоты | external-snapshotter в `kube-system` (6 CRD, включая экспериментальные `groupsnapshot.storage.k8s.io` — так устроен апстримный каталог CRD) |

Что даёт: снапшоты и бэкапы томов, клонирование PVC, расширение, RWX через share-manager,
шифрование, UI и метрики — то есть «взрослый» CSI вместо `local-path-provisioner`.

Чего НЕ делает: не становится StorageClass по умолчанию. `local-path` остаётся default,
Longhorn подключается явным `storageClassName` в PVC. Тома Longhorn живут по своим правилам
(1 реплика, свои пороги по диску), и смешивать их с молчаливым дефолтом не стоит.

Соглашение по политике: класс **без суффикса — Delete** (том уходит вместе с PVC, страховка —
снапшоты и бэкапы), а `-retain` явно помечает Retain для того, что нельзя потерять из-за
опечатки в `kubectl delete pvc`. Пока не настроен backup target, `longhorn` = «удаление PVC
стирает данные безвозвратно», поэтому для ценного без бэкапа брать `longhorn-retain`.

`oauth2-proxy` и `secure-headers` продублированы в `longhorn-system`: `ExtensionRef` ищет
`Middleware` рядом с маршрутом, а не в `traefik`.

Исследование по теме: [docs/research/k8s/storage-classes-and-csi-provisioners.md](../../docs/research/k8s/storage-classes-and-csi-provisioners.md).

## Почему недостаточно `kubectl apply` чарта

Четыре вещи, каждая из которых ломает Longhorn по-своему:

1. **`iscsid` не запущен.** Пакеты стоят, служба `inactive` — на Fedora это не редкость.
   Без неё iSCSI-тома не подключаются. Плейбук включает и запускает.
2. **SELinux (Fedora/RHEL/Rocky).** `iscsi-initiator-utils` создаёт каталоги в `/var/lib/iscsi`
   без execute-бита, а современный `container-selinux` не даёт `iscsid_t` capability
   `dac_override`. Симптом — все тома в цикле attach/detach. Плейбук ставит минимальный
   CIL-модуль (`infra/host/etc/selinux/local_longhorn.cil`). Альтернатива — DaemonSet из репозитория
   Longhorn: `deploy/prerequisite/longhorn-iscsi-selinux-workaround.yaml`.
3. **NFSv4-клиент и `kubeletRootDir`.** NFSv4 нужен для RWX и для backup target;
   k0s держит kubelet в `/var/lib/k0s/kubelet`, поэтому в values задан `csi.kubeletRootDir`
   (иначе драйвер монтирует staging-каталоги не туда).
4. **Отдельного диска нет.** Корень — XFS на LVM и ужать его нельзя, поэтому данные Longhorn
   лежат на корневой ФС (`/storage/apps/k8s/longhorn`). Из-за этого в values понижены пороги
   `storageMinimalAvailablePercentage: 10` и `storageReservedPercentageForDefaultDisk: 5`:
   при дефолтных 25/30 при свободных 16% диск сразу стал бы unschedulable.

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

- фактические числа на 2026-09-16: `storageMaximum` 474.3G, `storageAvailable` ~73-78G;
- `storageReservedPercentageForDefaultDisk: 5` даёт `spec.disks.*.storageReserved` ≈ 23.7 ГБ
  (в `status.diskStatus` этого поля в v1.12.1 нет — смотреть в spec диска или в UI);
- `storageMinimalAvailablePercentage: 10` требует держать свободными ~47 ГБ,
  то есть под данные остаётся ~25-30 ГБ, дальше диск становится unschedulable, а не убивает узел;
- потолок *выделения* шире (`StorageMax − Reserved` ≈ 450 ГБ), но он не спасёт от переполнения —
  реальный ограничитель это свободное место.

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

1. Прогнать `infra/ansible/host.yml` на новой ноде (или применить DaemonSet-обходной путь из
   `deploy/prerequisite/longhorn-iscsi-selinux-workaround.yaml`) и открыть порты Longhorn в
   firewalld (`infra/host/k0s/firewalld/`) — список портов в Longhorn docs, раздел Networking.
2. В Longhorn появится вторая нода с диском (`defaultDataPath` тот же). Диск — из отдельного
   раздела или диска, не из корня.
3. Поднять `numberOfReplicas: "2"` в `clusters/casa/platform/longhorn/storageclasses.yaml` и применить.
   Существующие тома придётся пересоздать/восстановить: изменить число реплик у живого тома
   можно только в UI (Volume → attach/detach связаны с PVC).
4. Пороги диска (`storageReservedPercentageForDefaultDisk`, `storageMinimalAvailablePercentage`)
   читаются при создании диска; для новой ноды глобальные значения уже подойдут. Менять их
   у существующей ноды — через UI или `kubectl -n longhorn-system edit settings.longhorn.io`.
5. Перевести backup target на внешнюю точку: одно-узловой rustfs перестаёт быть бэкапом.

Установка, проверка, возврат тома с `Retain`, грабли и удаление — в `RUNBOOK.md`.

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
