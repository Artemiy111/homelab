# Velero

Бэкапы и восстановление ресурсов Kubernetes и persistent-томов: восстановление
после отказа (disaster recovery), откат к состоянию на момент бэкапа, перенос
приложений между кластерами. Состоит из контроллера (deployment `velero`,
CRD `Backup`/`Restore`/`Schedule`), node agent (DaemonSet на каждом узле) и
плагинов.

## Что решено неочевидно

- Velero — не оператор. Отдельного «velero operator» чарта не существует и
  апстрим его не планирует: официальная распространённая форма установки —
  обычный Helm-чарт vmware-tanzu. Операторский контроль не нужен: объекты
  `Backup`/`Schedule` создаются вручную или CLI, их состояние следит сам
  контроллер.
- CSI-поддержка — не отдельный плагин, а feature-флаг: с Velero 1.14 CSI-логика
  встроена в ядро и включается значением `EnableCSI` в `configuration.features`.
  Бэкапы томов идут через нативный VolumeSnapshot API: snapshot-controller
  (external-snapshotter) и VolumeSnapshotClass'ы Longhorn уже в кластере, Velero
  выбирает класс у драйвера. Плагин velero-plugin-for-csi ставить не нужно.
- Без `BackupStorageLocation` бэкапы создать нельзя. Фаза 1 ставит контроллер
  без цели: `backupsEnabled: false` и `snapshotsEnabled: false`, иначе чарт
  рендерит default-BSL с пустым provider, который гарантированно битый. Когда
  появится S3-цель (кандидат — rustfs, но для настоящей DR нужен внешний:
  объектное хранилище вне кластера), BSL и VSL включаются в values, а
  credentials заводятся через VaultStaticSecret как `existingSecret` — в values
  секреты не кладутся никогда.
- Пути node agent указывают на /var/lib/k0s/kubelet — k0s держит kubelet не в
  /var/lib/kubelet. Смещение пути kubelet сломает fs-backup и data mover.
- Toleration ко всем taint'ам у контроллера и node agent: узел один и это
  control-plane, без них весь юнит стоит в Pending.
- ServiceMonitor/PodMonitor выключены: CRD prometheus-operator в кластере нет.
  Метрики на отдельном порту уже открыты, скрейп vmagent — вместе с фазой BSL.
- Velero работает с cluster-admin по умолчанию — это не оплошность, а природа
  задачи: он должен уметь читать и восстанавливать любой ресурс кластера, а
  секреты попадают в бэкап-архивы. Считать юнит привилегированной точкой входа;
  компрометация Velero равна root над кластером.

## Чего пока нет (фаза 1)

- BackupStorageLocation и VolumeSnapshotLocation отсутствуют: установка
  ограничена CRD, контроллером и node agent. Без BSL создание бэкапов невозможно
  по определению — это следующий шаг, фаза 2.
- Расписаний (`Schedule`) и hook'ов нет.
- Метрики не скрейпятся vmagent.

Слой Kubernetes-ресурсов бэкапится через Argo (git), тома — ближе к фазе 2
через CSI-снапшоты Longhorn + BSL.

## RUNBOOK

См. [RUNBOOK.md](RUNBOOK.md).
