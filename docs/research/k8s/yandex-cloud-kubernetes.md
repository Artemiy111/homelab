# Kubernetes в Yandex Cloud: Managed Service for Kubernetes, StorageClass и CRD

> Sources: исходники документации Yandex Cloud — репозиторий [`yandex-cloud/docs`](https://github.com/yandex-cloud/docs)
> (ветка `master`, файлы `en/managed-kubernetes/**`, `en/_includes/managed-kubernetes/**`, `en/_qa/managed-kubernetes/**`,
> `en/_includes/managed-kube-limits.md`, `presets.yaml`), доступные через `raw.githubusercontent.com` (сайт
> `yandex.cloud` отдаёт SmartCaptcha и напрямую не читается);
> GitHub-репозитории Yandex Cloud — [`yc-csi-driver`](https://github.com/yandex-cloud/yc-csi-driver),
> [`yc-alb-ingress-controller`](https://github.com/yandex-cloud/yc-alb-ingress-controller),
> [`k8s-csi-s3`](https://github.com/yandex-cloud/k8s-csi-s3),
> [`k8s-cloud-connectors`](https://github.com/yandex-cloud/k8s-cloud-connectors),
> [`crossplane-provider-yc`](https://github.com/yandex-cloud/crossplane-provider-yc),
> [`cert-manager-webhook-yandex`](https://github.com/yandex-cloud/cert-manager-webhook-yandex),
> [`cq-source-yc`](https://github.com/yandex-cloud/cq-source-yc),
> [`yc-guest-agent`](https://github.com/yandex-cloud/yc-guest-agent);
> Helm-репозиторий [`yandex-cloud.github.io/k8s-csi-s3/charts`](https://yandex-cloud.github.io/k8s-csi-s3/charts/index.yaml);
> GitHub REST API на 2026-09-18 (звёзды, теги, даты push).

Дата исследования: 2026-09-18. Кластер в этом репозитории — k0s **v1.36.3+k0s.2** на одном узле,
CNI Calico v3.32.1, `local-path-provisioner` (см. `k8s/k0s/README.md`). Ветка upstream Kubernetes — **v1.37**;
MK8S отстаёт: по release notes поддержка 1.34/1.35 добавлялась в Q4 2025 — Q1 2026, а таблица версий
(`presets.yaml`) на дату исследования называет новейшей в `RAPID` версию **1.34**
([Support for k8s versions](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/k8s-supported-versions.md),
[presets.yaml](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/presets.yaml),
[release-notes.md](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/release-notes.md)).

Смежные исследования: [storage-classes-and-csi-provisioners.md](./storage-classes-and-csi-provisioners.md),
[ingress-controllers-and-gateway-api.md](./ingress-controllers-and-gateway-api.md),
[cni-solutions.md](./cni-solutions.md),
[k0s-kubernetes-distribution.md](./k0s-kubernetes-distribution.md),
[gitops-repo-structure.md](./gitops-repo-structure.md).

---

## 1. Ответ на исходный вопрос

Вопрос был: «есть ли у Yandex Cloud свои StorageClass или CRD для Kubernetes?»

**Да, и то, и другое — но это разные вещи.**

1. **StorageClass — есть, но это НЕ CRD.** `StorageClass` — стандартный core-объект API `storage.k8s.io/v1`,
   который есть в любом Kubernetes. YC просто поставляет свои объекты этого типа (и CSI-драйвер, который за
   ними стоит). В MK8S предустановлены четыре класса: `yc-network-hdd` (default), `yc-network-ssd`,
   `yc-network-ssd-nonreplicated`, `yc-network-ssd-io-m3`, все с provisioner `disk-csi-driver.mks.ycloud.io`
   ([Managing storage classes](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/operations/volumes/manage-storage-class.md)).
2. **CRD — есть, в экосистеме Application Load Balancer.** Классический ALB Ingress Controller вводит
   группу **`alb.yc.io/v1alpha1`** (`HttpBackendGroup`, `GrpcBackendGroup`, `IngressGroupSettings`,
   `IngressGroupStatus`) ([HttpBackendGroup](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/alb-ref/http-backend-group.md),
   [API types](https://raw.githubusercontent.com/yandex-cloud/yc-alb-ingress-controller/main/api/v1alpha1/groupversion_info.go)).
   Новый рекомендованный контроллер **Gwin** вводит группу **`gwin.yandex.cloud/v1`**
   (`IngressPolicy`, `IngressBackendGroup`, `GatewayPolicy`, `RoutePolicy`, `ServicePolicy`, `YCCertificate`,
   `YCStorageBucket` и др.) ([Gwin controller](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/alb-ref/gwin-index.md),
   [Gwin policies](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/alb-ref/gwin-policies.md)).

То есть «StorageClass» и «CRD» здесь не конкурируют: StorageClass — core-API для хранилища, CRD — расширения
для L7-балансировщика. Никакого CRD `StorageClass` у YC нет и быть не может — это не расширяемый объект.

---

## 2. Что такое Yandex Managed Service for Kubernetes (MK8S)

### 2.1. Базовая модель

Кластер MK8S состоит из **master** (управляется YC) и одного или нескольких **node groups** — групп
виртуальных машин Compute с одинаковой конфигурацией; на узлах работают контейнеры пользователя
([Resource relationships](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/index.md)).
Master запускает control plane (kube-apiserver, scheduler, контроллеры), пользователь не имеет к нему доступа;
YC «полностью управляет master» ([General FAQ](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_qa/managed-kubernetes/general.md)).

| Сущность | Что это |
|---|---|
| **Кластер** | master + node groups + сетевые диапазоны (pods/services) + release channel |
| **Master** | управляемый control plane; варианты Base (1 хост в 1 зоне) и Highly available (3 хоста) |
| **Node group** | Compute instance group: одинаковые VM, containerd как единственный runtime |
| **Namespace / Service / Pod** | обычные объекты Kubernetes; Service типа `LoadBalancer` через YC NLB |

Master по умолчанию: Intel Cascade Lake, гарантированная доля vCPU 100%, **2 vCPU / 8 GB RAM**
([master-default-config](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/master-default-config.md)).
Доступны конфигурации Standard (4:1 RAM:vCPU), CPU-optimized (2:1), Memory-optimized (8:1), вплоть до
80 vCPU / 320 GB, и **master autoscaling**, где выбранная конфигурация — нижняя граница
([Master computing resources](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/index.md),
[Master autoscaling](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/autoscale.md)).

### 2.2. Зоны, версии, обновления

- **Highly available master** размещается в одной зоне (ниже latency) или в трёх зонах (лучшая отказоустойчивость);
  внутренний IP HA-мастера доступен только внутри одной облачной сети ([Master](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/index.md)).
- **Release channels**: `RAPID` (автообновления нельзя отключить), `REGULAR`, `STABLE` (автообновления
  отключаемы). Канал задаётся при создании кластера и не меняется — только пересоздание
  ([Release channels](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/release-channels-and-updates.md)).
- Версии master и node group независимы. Разница — **не более двух минорных**, версия node group не может быть
  выше версии кластера. Ручное обновление — только на следующий минор (1.31→1.32), за один шаг
  ([Release channels](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/release-channels-and-updates.md),
  [Updating k8s](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/operations/update-kubernetes.md)).
- **Обязательные (required) обновления** отключить нельзя; без окна обновления по умолчанию ставятся через
  14 дней, дату можно сдвинуть ([Required update](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/release-channels-and-updates.md)).
- Сертификаты кластера/узлов живут **1 год** и ротируются автоматически (принудительно — за неделю до истечения)
  ([Certificates](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/release-channels-and-updates.md)).

### 2.3. Кто платит за master и SLA

Биллинг MK8S: платный **master** + исходящий трафик; узлы — по тарифам Compute
([Pricing policy](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/pricing.md)).
**У остановленного кластера master не тарифицируется**, но диски, публичные IP и сетевые балансировщики
продолжают стоить ([Pricing policy](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/pricing.md)).

SLA: документация прямо привязывает Service Level Agreement к конфигурации **с HA-master в трёх зонах**
(«The {{ managed-k8s-name }} Service Level Agreement applies to the configuration with a highly available
master running across three zones») ([Recommendations](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/usage-recommendations.md)).
Конкретный процент SLA на странице yandex.cloud проверить не удалось (SmartCaptcha) — **не подтверждено
первоисточником в этом исследовании**.

### 2.4. Квоты и лимиты (ключевое)

Из `_includes/managed-kube-limits.md` ([источник](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kube-limits.md)):

| Лимит | Значение |
|---|---|
| Кластеров на облако | 10 |
| Node groups на облако / на кластер | 160 / 32 |
| Узлов на облако / на кластер / на группу | 160 / 200 / 200 |
| vCPU всех нод на облако | 240 |
| RAM всех нод на облако | 960 GB |
| Дисковое пространство всех нод на облако | 30 000 GB |
| vCPU всех мастеров / RAM всех мастеров | 60 / 240 GB |
| Томов на один узел | 56 |

Стандартный лимит Kubernetes — **110 подов на узел**
([Networking](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/network.md)).
Для autoscaling-групп в квотах учитывается **максимальный** размер группы, а не текущий
([Autoscaling](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/autoscale.md)).

---

## 3. Хранилище

### 3.1. CSI-драйвер `yc-csi-driver`

- **Provisioner/driver name: `disk-csi-driver.mks.ycloud.io`** — строковая константа в исходниках
  ([`pkg/services/constants.go`](https://raw.githubusercontent.com/yandex-cloud/yc-csi-driver/master/pkg/services/constants.go)),
  совпадает с именем `CSIDriver` ([`deploy/v1.2.0/driver.yaml`](https://raw.githubusercontent.com/yandex-cloud/yc-csi-driver/master/deploy/v1.2.0/driver.yaml)).
- Публичный репозиторий `yandex-cloud/yc-csi-driver` — Apache-2.0, но **очень маленький и тихий**: 8 звёзд,
  последний релиз **v1.2.0 (2026-02-27)**, последний push 2026-02-27 (GitHub API на 2026-09-18). В MK8S
  поставляется встроенная сборка; по публичному репо судить её версию нельзя.
- `CSIDriver`: `attachRequired: true`, `podInfoOnMount: true` ([driver.yaml](https://raw.githubusercontent.com/yandex-cloud/yc-csi-driver/master/deploy/v1.2.0/driver.yaml)).
- Controller — Deployment из четырёх контейнеров: сам драйвер + sidecar'ы **csi-provisioner v5.2.0,
  csi-attacher v4.8.1, csi-resizer v1.13.2, livenessprobe v2.15.0**; Node — DaemonSet с node-driver-registrar.
  ([controller.yaml](https://raw.githubusercontent.com/yandex-cloud/yc-csi-driver/master/deploy/v1.2.0/controller.yaml),
  [node.yaml](https://raw.githubusercontent.com/yandex-cloud/yc-csi-driver/master/deploy/v1.2.0/node.yaml)).
- **В MK8S драйвер предустановлен.** Для self-managed кластера нужны: SA с ролью `k8s.clusters.agent`,
  Secret `yc-csi-sa-key`, ConfigMap `yc-csi-config` с `folderId`, затем `kubectl apply -f deploy/vX.Y.Z`
  ([README драйвера](https://raw.githubusercontent.com/yandex-cloud/yc-csi-driver/master/README.md)).
  Это отдельная операционная работа (IAM-ключ, RBAC, отсутствие автоматических обновлений).

### 3.2. Диски, StorageClass, default, resize

Поддерживаемые типы дисков Compute (параметр `type` в StorageClass):

| Тип | Класс по умолчанию | Комментарий |
|---|---|---|
| `network-hdd` | `yc-network-hdd` | сетевой HDD |
| `network-ssd` | `yc-network-ssd` | сетевой SSD |
| `network-ssd-nonreplicated` | `yc-network-ssd-nonreplicated` | non-replicated SSD, **без избыточности** — при отказе данные теряются |
| `network-ssd-io-m3` | `yc-network-ssd-io-m3` | сверхбыстрый SSD с тремя репликами |

([Managing storage classes](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/operations/volumes/manage-storage-class.md),
[non-replicated note](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/nrd-no-backup-note.md)).
Класс **`yc-network-nvme` устарел**, вместо него `yc-network-ssd`
([Managing storage classes](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/operations/volumes/manage-storage-class.md)).
Прочие параметры: `csi.storage.k8s.io/fstype` (`ext2/ext3/ext4/btrfs`), `blockSize`
(`4096`…`131072`, по умолчанию 4096), `reclaimPolicy` (`Retain`/`Delete`), `allowVolumeExpansion`
([там же](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/operations/volumes/manage-storage-class.md)).

Свойства классов и провижионинга:

| Свойство | Значение | Источник |
|---|---|---|
| Default-класс | `yc-network-hdd` | [dynamic-create-pv](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/operations/volumes/dynamic-create-pv.md) |
| `volumeBindingMode` | `WaitForFirstConsumer` | [manage-storage-class](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/operations/volumes/manage-storage-class.md) |
| `reclaimPolicy` | `Delete` | там же |
| `allowVolumeExpansion` | в документации «включено по умолчанию» (`true`) | [volume-expansion](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/operations/volumes/volume-expansion.md) |
| Режим доступа | документация: только `ReadWriteOnce` | [manage-storage-class](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/operations/volumes/manage-storage-class.md) |
| `volumeMode` | `Filesystem` (default) или `Block` | [volume.md](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/volume.md) |
| Расширение | online, без пересоздания пода (по доке) | [volume-expansion](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/operations/volumes/volume-expansion.md) |

**Важное расхождение первоисточников.** Манифесты в публичном репозитории драйвера
([`deploy/v1.2.0/storage-class.yaml`](https://raw.githubusercontent.com/yandex-cloud/yc-csi-driver/master/deploy/v1.2.0/storage-class.yaml))
задают `allowVolumeExpansion: false` и содержат только два класса (`yc-network-hdd`, `yc-network-ssd`).
Документация MK8S описывает четыре класса, default `yc-network-hdd` и `allowVolumeExpansion: true`
(в `kubectl get storageclass` в примерах колонка `ALLOWVOLUMEEXPANSION` = `true`). Вывод: **предустановленные
классы в MK8S отличаются от манифестов в публичном репо**; для self-managed установки из репо расширение
томов нужно включать правкой класса.
Также в коде `ProductionCapsForPublicAPIController` объявлена capability **`EXPAND_VOLUME`**, но плагин
заявляет `VolumeExpansion_OFFLINE` ([`constants.go`](https://raw.githubusercontent.com/yandex-cloud/yc-csi-driver/master/pkg/services/constants.go));
заявление доки об *online*-расширении этому противоречит — считать подтверждённым только «расширение
поддерживается», а online-деталь — под вопросом.

Дополнительно: статически созданные PV всегда получают `persistentVolumeReclaimPolicy: Retain`, и при удалении
кластера диски PV **не удаляются автоматически**; для динамических томов удаление PVC удаляет и диск
([volume.md](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/volume.md),
[cluster delete note](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/note-k8s-cluster-delete.md)).

### 3.3. Шифрование дисков и секретов (KMS)

- В StorageClass можно указать `kmsKeyId: <symmetric_key_ID>` — динамически создаваемый диск будет зашифрован
  ключом KMS; для статических PV используют уже зашифрованный диск
  ([encrypted storage class](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/encrypted-storage-class-config.md),
  [volume.md](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/volume.md)).
- **Секреты Kubernetes** шифруются ключом KMS, если ключ указан **при создании кластера**; сменить ключ позже
  нельзя — только новый кластер. Используется KMS provider и envelope encryption
  ([Encryption](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/encryption.md)).
- Диски в YC и так шифруются системными ключами при передаче в хранилище, но ключи YC — не ваши;
  пользовательский KMS-ключ даёт аудит и ротацию ([Encryption](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/encryption.md)).

### 3.4. Снапшоты: есть в коде, но не как продукт

Тонкий момент. В исходниках драйвера **реализованы** `CreateSnapshot`/`DeleteSnapshot`/`ListSnapshots` и
`CreateVolume` из снапшота ([`pkg/services/controller/controller.go`](https://raw.githubusercontent.com/yandex-cloud/yc-csi-driver/master/pkg/services/controller/controller.go)).
**Но в production-capability-наборе** `ProductionCapsForPublicAPIController` снапшот-возможности
(`CREATE_DELETE_SNAPSHOT`, `LIST_SNAPSHOTS`) отсутствуют — они объявлены только в тестовом `SanityControllerCaps`
([`constants.go`](https://raw.githubusercontent.com/yandex-cloud/yc-csi-driver/master/pkg/services/constants.go)).
Кроме того, в `controller.yaml` **нет sidecar `csi-snapshotter`**, и ни в доке MK8S, ни в репо нет
`VolumeSnapshotClass`.

Вывод: **штатные CSI-снапшоты (`VolumeSnapshot`) для `yc-csi-driver` не предоставляются** — копии дисков в YC
есть как облачные ресурсы Compute, но не как Kubernetes `VolumeSnapshot` API. Первоисточником это явно не
опровергнуто (в доке просто нет раздела про VolumeSnapshot), поэтому формулирую как «не поддержано в
production-конфигурации драйвера». Для бэкапов ориентируйтесь на сторонние инструменты (Velero с файловым
бэкапом, restic/kopia) — как и в [storage-classes-and-csi-provisioners.md](./storage-classes-and-csi-provisioners.md#78-бэкапы-pv-и-почему-снапшоты--бэкап).

### 3.5. Object Storage: варианты доступа из Kubernetes

**Официального «встроенного» CSI для Object Storage в MK8S нет** — S3-бакеты не подключаются как
предустановленный StorageClass. Есть драйвер, публикуемый Yandex Cloud в Marketplace:

- [`yandex-cloud/k8s-csi-s3`](https://github.com/yandex-cloud/k8s-csi-s3) — **GeeseFS-based CSI** поверх S3
  (FUSE-маунт), 885 звёзд, последний релиз **v0.43.7 (2026-05-05)** (GitHub API на 2026-09-18).
- Provisioner — **`ru.yandex.s3.csi`**, параметр `mounter: geesefs`, endpoint `https://storage.yandexcloud.net`,
  доступны **dynamic и static** PV, режим **RWX**
  ([Integration with Object Storage](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/operations/volumes/s3-csi-integration.md)).
- Установка: из Marketplace или вручную (`secret.yaml` + `provisioner.yaml` + `driver.yaml` + `csi-s3.yaml`
  + StorageClass `csi-s3`) ([там же](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/operations/volumes/s3-csi-integration.md)).
  Helm-чарт публикуется в `https://yandex-cloud.github.io/k8s-csi-s3/charts`
  ([index.yaml](https://yandex-cloud.github.io/k8s-csi-s3/charts/index.yaml)).
- Требования/ограничения: **privileged-контейнеры и FUSE**, версия Kubernetes 1.17+, в README указан флаг
  докера `MountFlags=shared` ([README](https://raw.githubusercontent.com/yandex-cloud/k8s-csi-s3/master/README.md)).
  Практически: S3 через GeeseFS — это POSIX-подобный слой с кэшем, а не блочный диск; для БД не годится,
  для shared-контента/артефактов — рабочий вариант.

**Оценка пригодности.** Для homelab с уже имеющимся S3 (в этом репозитории — rustfs) S3-CSI даёт «дешёвый»
RWX без NFS-сервера. Но: FUSE + privileged + нет снапшотов, выше latency, поведение при конкурентной записи
не как у FS — держите его для не-БД нагрузок. Альтернатива без CSI — работа через SDK/init-контейнеры
(s3cmd/aws-cli), что проще, но не даёт PVC-абстракции.

### 3.6. Диски vs managed-сервисы YC

Документация MK8S прямо не рекомендует поднимать stateful-нагрузки (особенно БД) на PV внутри кластера и
советует использовать **managed-сервисы** YC (Managed PostgreSQL/MySQL/ClickHouse/YDB): «We do not recommend
running stateful services with persistent volumes in k8s» ([FAQ volumes](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_qa/managed-kubernetes/volumes.md)).
Логика: managed-БД берёт на себя бэкапы, HA, патчи и обновления, а PV на сетевом диске — это RWO и bound
к зоне. Для homelab-обучения Kubernetes это важно как контекст: «в проде БД выносят из кластера».

---

## 4. CRD и расширения от Yandex Cloud

### 4.1. ALB Ingress Controller (`alb.yc.io/v1alpha1`)

Репозиторий [`yandex-cloud/yc-alb-ingress-controller`](https://github.com/yandex-cloud/yc-alb-ingress-controller):
Apache-2.0-подобная лицензия (GitHub показывает `NOASSERTION`), 9 звёзд, последний push **2026-06-29**,
**тегов и GitHub-релизов нет** (GitHub API на 2026-09-18) — распространяется через OCI-чарт и Marketplace.

CRD группы `alb.yc.io` ([groupversion_info.go](https://raw.githubusercontent.com/yandex-cloud/yc-alb-ingress-controller/main/api/v1alpha1/groupversion_info.go),
[config/crd/bases](https://github.com/yandex-cloud/yc-alb-ingress-controller/tree/main/config/crd/bases)):

| CRD | Scope | Назначение |
|---|---|---|
| `HttpBackendGroup` | namespaced | группа HTTP-бэкендов: `weight`, `useHttp2`, `service`/`storageBucket`, `tls` (sni/trustedCa), `healthChecks`, `loadBalancingConfig`, `sessionAffinity` |
| `GrpcBackendGroup` | namespaced | то же для gRPC: `weight`, `service`, `tls`, gRPC-health-checks |
| `IngressGroupSettings` | cluster | настройки логирования группы Ingress (`logOptions`: log group, discard rules) |
| `IngressGroupStatus` | cluster | статус: ID балансировщика, роутеров, backend/target groups |

Источники: [HttpBackendGroup](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/alb-ref/http-backend-group.md),
[GrpcBackendGroup](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/alb-ref/grpc-backend-group.md),
[ingressgroupsettings_types.go](https://raw.githubusercontent.com/yandex-cloud/yc-alb-ingress-controller/main/api/v1alpha1/ingressgroupsettings_types.go),
[ingressgroupstatus_types.go](https://raw.githubusercontent.com/yandex-cloud/yc-alb-ingress-controller/main/api/v1alpha1/ingressgroupstatus_types.go).

Что это решает: взвешивание и пропорциональное распределение трафика между бэкендами, кастомные health-check
(HTTP path/gRPC service), TLS до бэкенда, HTTP/2, режимы балансировки (`ROUND_ROBIN`, `RANDOM`,
`LEAST_REQUEST`, `MAGLEV_HASH`), panic mode, locality-aware routing, session affinity; бэкендом может быть
Kubernetes Service **или** бакет Object Storage
([HttpBackendGroup](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/alb-ref/http-backend-group.md)).
IngressClass controller name — **`ingress.alb.yc.io/yc-alb-ingress-controller`**
([IngressClass](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/alb-ref/ingress-class.md)).

Версии: README чарта показывает `VERSION=v0.1.3`
([helm/chart/README.md](https://raw.githubusercontent.com/yandex-cloud/yc-alb-ingress-controller/main/helm/chart/README.md)),
но документация обновления говорит про «версии 0.2.0 и новее» и «Helm-чарт версии 0.2.9 или выше»
([upgrade include](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/alb-ref/upgrade-alb-ingress-controller.md)).
Актуальную версию из первоисточника (Marketplace) получить не удалось из-за SmartCaptcha — **точная версия
не подтверждена**; ориентируйтесь на `0.2.9+`.

### 4.2. Gwin (`gwin.yandex.cloud/v1`) и Gateway API от ALB

Yandex Cloud развивает **новый контроллер Gwin** и в документации прямо рекомендует его **вместо**
ALB Ingress Controller и Gateway API: «We recommend using the new Yandex Cloud Gwin controller instead of an
ALB Ingress Controller and Gateway API» ([tip include](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/application-load-balancer/ingress-to-gwin-tip-with-preset.md)).

- Gwin поддерживает **и Ingress, и Gateway API**, а дополнительная конфигурация ALB делается через
  **policy-механизм**: аннотации `gwin.yandex.cloud/*` **или** CRD группы **`gwin.yandex.cloud/v1`**
  ([Gwin controller](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/alb-ref/gwin-index.md),
  [Gwin policies](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/alb-ref/gwin-policies.md)).
- CRD Gwin (по toc и gwin-ref): `GatewayPolicy`, `IngressPolicy`, `IngressBackendGroup`, `RoutePolicy`,
  `ServicePolicy`, `YCCertificate`, `YCStorageBucket`, `BackendTLSPolicy`, `DirectResponse`, `ListenerSet`,
  `ListenerSetPolicy` ([toc.yaml](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/toc.yaml),
  [gwin-ref](https://github.com/yandex-cloud/docs/tree/master/en/managed-kubernetes/gwin-ref)).
- GatewayClass/IngressClass — `gwin-default`; адрес — `gwin.yandex.cloud/autoIPv4`; TLS-сертификат —
  `YCCertificate` (`apiVersion: gwin.yandex.cloud/v1`), секьюрити-группы — аннотация
  `gwin.yandex.cloud/securityGroups` ([Gwin quickstart](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/alb-ref/gwin-quickstart.md)).
- Есть конвертер `alb-ingress-converter` (v1.0.0) для миграции `alb.yc.io` → Gwin: меняет
  `IngressClass` на `gwin-default`, аннотации `ingress.alb.yc.io/*` → `gwin.yandex.cloud/*`,
  `HttpBackendGroup`/`GrpcBackendGroup` → `IngressBackendGroup`, бакеты → `YCStorageBucket`
  ([ingress-gwin-migration](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/alb-ref/ingress-gwin-migration.md)).

Отдельно от Gwin существует **Gateway API от ALB** (продукт `gateway-api` в Marketplace): `Gateway` создаёт
L7-балансировщик, `HTTPRoute`/`GRPCRoute` — маршруты; пример использует `gatewayClassName: yc-df-class`
([Gateway API overview](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/application-load-balancer/gateway-api/gateway-api.md)).
Установка — из Marketplace или Helm-чартом `oci://...gateway-api`; при апгрейде 0.6.0 CRD Gateway API
поднимаются с 0.6.2 до 1.2.1 ([gateway-api-install](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/gateway-api-install.md)).
Точные версии чартов Gwin/Gateway API заданы переменными `mkt-k8s-key.*` и в исходнике не раскрыты —
**не подтверждены**.

### 4.3. Прочие CRD/инструменты YC

| Инструмент | Что даёт | Состояние (GitHub API 2026-09-18) |
|---|---|---|
| [`k8s-cloud-connectors`](https://github.com/yandex-cloud/k8s-cloud-connectors) | Интеграция YC-ресурсов в k8s через control-loop (cloud-controller-manager и др.) | 9 ⭐, последний push **2022-08-04**, теги `0.0.1`/`0.1.0` — фактически не развивается |
| [`crossplane-provider-yc`](https://github.com/yandex-cloud/crossplane-provider-yc) | Crossplane-провайдер: managed resources YC (Upjet), последний тег **v0.14.0** | 44 ⭐, push 2026-08-27 |
| [`cert-manager-webhook-yandex`](https://github.com/yandex-cloud/cert-manager-webhook-yandex) | DNS-01 webhook для cert-manager: `solverName: yandex-cloud-dns`, `groupName: acme.cloud.yandex.com` | 25 ⭐, push 2026-07-15 |
| [`cq-source-yc`](https://github.com/yandex-cloud/cq-source-yc) | CloudQuery source-плагин для YC API | есть `v1.0.0` |
| [`yc-guest-agent`](https://github.com/yandex-cloud/yc-guest-agent) | Сброс пароля гостевой ОС VM, **не** про Kubernetes | — |
| Crossplane в Marketplace | При установке из Marketplace сразу ставится провайдер `crossplane-provider-yc` ([info](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/crossplane-provider-info.md)) | — |

Мораль: Kubernetes-экосистема YC сосредоточена вокруг MK8S, ALB/Gwin и storage; Crossplane есть, но для
обычного homelab это лишний слой.

---

## 5. Сетевая модель MK8S

### 5.1. Диапазоны, поды, узлы

- При создании задаются: сеть/подсеть master, IPv4-диапазон **pods**, диапазон **services**, маска подсети
  узлов ([Networking](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/network.md)).
- В режиме без tunnel mode доступна только **половина** диапазона, диапазоны не должны пересекаться; доступны
  `10.0.0.0/8`, `172.16.0.0/12`, `<lan-cidr>`. Маска подсети узлов и размер pod-диапазона определяют
  максимальное число узлов и подов.
  Пример из доки: pods `10.1.0.0/16`, nodes mask `24` → диапазоны узлов `10.1.128.0/24`–`10.1.255.0/24`,
  по ~254 адреса на узел.
- Стандартный лимит Kubernetes — **110 подов на узел** ([Networking](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/network.md)).
- **Tunnel mode (Cilium)**: сеть на VxLAN, разрешены пересекающиеся диапазоны, диапазон до `/8`, вдвое больше
  узлов; нужна роль `k8s.tunnelClusters.agent` ([Network policies](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/network-policy.md)).
- IP-маскарадинг подов делает `ip-masq-agent` (ConfigMap `ip-masq-agent`, `nonMasqueradeCIDRs`)
  ([Resource relationships](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/index.md)).

### 5.2. NetworkPolicy и CNI

- MK8S использует **Calico** (iptables) или **Cilium** (eBPF) как контроллеры сетевых политик; включаются
  **только при создании кластера** и **взаимоисключающе**: «You cannot enable the Calico network policy
  controller and the Cilium tunnel mode at the same time» ([Network policies](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/network-policy.md),
  [mutual exclusion](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/calico-cilium-mutual-exclusion.md)).
- Cilium умеет L7-политики, DNS-based политики и Hubble ([Network policies](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/network-policy.md)).
- `loadBalancerSourceRanges` в MK8S **не поддерживается**; для ограничения доступа к LB используйте
  NetworkPolicy ([Network policies](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/network-policy.md)).
- **Какой CNI обеспечивает pod-to-pod связность по умолчанию, когда ни Calico, ни Cilium не включены,
  в проверенных исходниках прямо не сказано** — не подтверждено. Точно известно только, что Cilium в tunnel
  mode выступает как CNI.

### 5.3. Service LoadBalancer, статические IP, Security Groups

- Типы Service: `ClusterIP`, `NodePort`, `LoadBalancer`; `LoadBalancer` создаёт **сетевой балансировщик YC**
  (публичный или внутренний) ([Service](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/service.md)).
- Статический публичный IP — поле `loadBalancerIP` (адрес резервируется заранее), можно включить
  DDoS-защиту; статический IP LB не меняется при обновлении node group
  ([create-load-balancer](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/operations/create-load-balancer.md)).
- **MetalLB не нужен и не используется**: внешний адрес даёт облачный NLB. (В отличие от нашего homelab,
  где MetalLB удалён и Traefik держит `externalIPs` — см. [ingress-controllers-and-gateway-api.md](./ingress-controllers-and-gateway-api.md#8-что-стоит-в-homelab-сейчас-и-варианты-миграции).)
- **Security Groups** — это объекты VPC, а не CRD: они назначаются кластеру/группе узлов и настраиваются
  через CLI/TF/API; для LB их ID передаются аннотациями Ingress (`ingress.alb.yc.io/security-groups`),
  Gateway (`gateway.alb.yc.io/security-groups`) или Gwin (`gwin.yandex.cloud/securityGroups`)
  ([Security groups for ALB tools](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/alb-ref/security-groups.md),
  [connect/security-groups](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/operations/connect/security-groups.md)).
  **CRD вида `securitygroups.yandex.cloud` в проверенных первоисточниках не обнаружено** — если кто-то
  утверждает обратное, это требует отдельного подтверждения.
- Публичный доступ включается отдельно для master (только при создании) и для node group (создание/обновление)
  ([Networking](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/network.md)).

---

## 6. Эксплуатация

### 6.1. Обновления и maintenance

- Автообновления master и node group настраиваются независимо: отключены / anytime / daily / weekly окно в UTC
  ([Updating k8s](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/operations/update-kubernetes.md)).
- Basic master **недоступен** во время обновления, HA master сохраняет сетевую связность
  ([Release channels](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/release-channels-and-updates.md)).
- Обновления без смены версии (`--latest-revision`) ставят новые пакеты/патчи/образ
  ([Updating k8s](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/operations/update-kubernetes.md)).

### 6.2. Deploy policy, drain, PodDisruptionBudget

- Политика обновления node group — пара `max_expansion` (default **3**) и `max_unavailable` (default **0**);
  хотя бы один должен быть > 0 ([Deploy policy](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/node-group/deploy-policy.md)).
- При обновлении/сжатии узлы **drain'ятся по одному**; таймаут остановки узла — **7 минут**, после чего узел
  останавливается даже если не все поды выселены. Pod без контроллера (ReplicaSet/Deployment/StatefulSet)
  при этом теряется; для управляемого выселения нужен `PodDisruptionBudget`
  ([Evicting pods](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/node-group/node-drain.md)).
- Узлы не drain'ятся при **удалении** node group — правильный путь: уменьшить группу до нуля, дождаться и
  удалить ([там же](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/node-group/node-drain.md)).

### 6.3. Autoscaling

- **Cluster autoscaler**: min/max/initial узлов, включается только при создании группы, управляется на стороне
  MK8S; autoscaling-группа живёт **только в одной зоне**
  ([Cluster autoscaler](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/node-group/cluster-autoscaler.md)).
- **HPA** (по vCPU) и **VPA** (`Off`/`Initial`/`Recreate`/`InPlaceOrRecreate`); HPA+VPA вместе не рекомендуются
  ([Autoscaling](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/autoscale.md)).
- **Master autoscaler** (см. 2.1).

### 6.4. GPU, прерываемые (preemptible) ноды, taints/labels

- **GPU-группы**: нужна ненулевая GPU-квота и правильные зоны; образ VM с NVIDIA-драйверами и CUDA; для
  кластеров 1.35+ используется cgroup v2
  ([GPU node groups](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/node-group/node-group-gpu.md),
  [cgroups-v2 include](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/cgroups-v2-platform.md)).
- **Preemptible VM**: флаг `--preemptible` / `preemptible = true`. Документация советует для автоматического
  вытеснения подов при остановке такие ноды использовать Marketplace-продукт **node-sitter**; автоматического
  taint'а для preemptible-нод в проверенных исходниках **не описано** — не подтверждено
  ([node-group-create](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/operations/node-group/node-group-create.md),
  [note-preemptible-vm](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/note-preemptible-vm.md)).
- **Taints** задаются на группу при создании (в TF — правкой, что пересоздаёт группу): эффекты
  `NO_SCHEDULE`, `PREFER_NO_SCHEDULE`, `NO_EXECUTE`; системным подам tolerations добавляются автоматически
  ([Resource relationships](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/index.md)).
- **Labels**: cloud labels (`template-labels` / `labels` в TF) для биллинга, Kubernetes-лейблы
  (`node-labels` / `node_labels`) для планирования; лейблы, добавленные через k8s API, могут пропасть при
  пересоздании узлов — надёжнее через MK8S API ([там же](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/index.md)).

### 6.5. IAM, RBAC, Workload Identity, KMS

- Два сервис-аккаунта: **cluster SA** (`k8s.clusters.agent`; управляет узлами, подсетями, дисками, LB,
  шифрованием секретов) и **node group SA** (аутентификация в Container Registry / Cloud Registry).
  Для tunnel mode — `k8s.tunnelClusters.agent`
  ([Access management](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/security/index.md)).
- Доступ к k8s API — роли `k8s.cluster-api.viewer/editor/admin/cluster-admin` + обычный RBAC
  ([Access management](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/security/index.md)).
- **Workload Identity Federation (WLIF)**: MK8S создаёт OIDC-провайдера для кластера и выдаёт `issuer` и
  `jwks_uri`; включается на кластере и node group, позволяет подам получать IAM-токен без долгоживущих ключей
  ([WLIF integration](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/operations/kubernetes-cluster/kubernetes-cluster-wlif-integration.md),
  [WLIF description](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/wlif-mk8s-description.md)).
- **Шифрование секретов KMS** — только при создании кластера (см. 3.3).

### 6.6. External nodes (Preview)

Можно подключать серверы **вне YC** как узлы кластера: требуется L3-связность (Interconnect/VPN), **tunnel
mode**, Ubuntu 24.04, интернет. Ограничения: PV на дисках YC и L3-LoadBalancer к таким узлам не работают;
балансировку делать L7-ingress'ом, причём ALB Ingress Controller и Gateway API external nodes **не
поддерживают** — только **Gwin** ([External nodes](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/concepts/external-nodes.md)).
Функция в Preview и не тарифицируется на дату исследования.

---

## 7. Логи, метрики, IaC

### 7.1. Метрики и логи

- MK8S **автоматически** отправляет метрики в YC Monitoring по container/master/node/pod/persistent volume;
  смотреть можно в консоли, Monitoring UI/API, а также через Marketplace `metrics-provider` и
  `prometheus-operator` ([Metrics](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/metrics.md),
  [resources list](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/metrics-resources-list.md)).
- **Логи master** можно отправлять в Cloud Logging: `kube-apiserver`, `cluster-autoscaler`, события Kubernetes,
  audit-события; настраивается только через CLI/TF/API (в консоли нет)
  ([FAQ logs](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_qa/managed-kubernetes/logs.md),
  [master logging](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/master-logging-cli-description.md)).
- Логи приложений — через **Fluent Bit** (или свой стек); операции с ресурсами — `yc managed-kubernetes
  cluster list-operations` / `yc operation get` и Audit Trails
  ([Operations](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/operations/kubernetes-cluster/kubernetes-cluster-operation-logs.md)).

### 7.2. IaC

- **Terraform**: `yandex_kubernetes_cluster`, `yandex_kubernetes_node_group`, `yandex_kubernetes_cluster_iam_binding`
  / `_iam_member` + data sources ([TF reference](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/tf-ref.md)).
- Можно активировать provider `kubernetes` (`hashicorp/kubernetes`) и управлять k8s-ресурсами тем же TF,
  а `helm`-провайдером — ставить чарты ([apply-tf-provider](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/operations/apply-tf-provider.md),
  [apply-helm-provider](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/managed-kubernetes/operations/apply-helm-provider.md)).
- **Crossplane** (`crossplane-provider-yc`) — managed resources YC; ставится из Marketplace или xpkg
  ([Crossplane info](https://raw.githubusercontent.com/yandex-cloud/docs/master/en/_includes/managed-kubernetes/crossplane-provider-info.md),
  [README](https://raw.githubusercontent.com/yandex-cloud/crossplane-provider-yc/main/README.md)).

---

## 8. MK8S vs self-managed Kubernetes на YC vs наш homelab на k0s

### 8.1. Сравнение

| Критерий | MK8S | Self-managed на VM YC (k0s/kubeadm) | Наш homelab (k0s, bare metal) |
|---|---|---|---|
| Control plane | управляет YC, к master доступа нет | вы сами: HA, etcd, сертификаты, апгрейды | k0s, один узел, control plane у вас |
| Обновления | release channels, maintenance window, required updates | полностью на вас | полностью на вас (k0s-версия своя) |
| Хранилище | предустановленный `yc-csi-driver` + 4 класса | CSI ставить руками (SA-ключ, RBAC, свои manifests) | local-path-provisioner |
| LoadBalancer Service | встроенная интеграция с NLB (статический IP, DDoS) | нужен cloud-controller-manager (`k8s-cloud-connectors`, репо stale) или ручной NLB | MetalLB удалён; Traefik на `externalIPs` |
| Сеть/CNI | Calico/Cilium опционально; NLB; SG через API | выбираете сами (см. [cni-solutions.md](./cni-solutions.md)) | Calico vxlan |
| IAM/RBAC/OIDC | YC IAM + RBAC + WLIF из коробки | настраивать самому | homelab-схема на Tailscale/Technitium |
| SLA | по договору для HA-master в 3 зонах | нет (ваша ответственность) | нет |
| Стоимость | платный master + compute + egress | только compute + диски + egress | своё железо |
| Вендор-лок | API/IAM/ALB/диски YC | средний | минимальный |

### 8.2. Когда что выбирать

- **MK8S** — если нужен прод-контур с SLA, интеграцией с IAM/ALB/Logging/Monitoring и минимумом операционной
  работы. Минус — платный master и меньше контроля над control plane/CNI (нельзя включить Calico после
  создания, нельзя ставить произвольный CNI).
- **Self-managed на VM** — если нужен полный контроль над CNI/версией/control plane или это учебная цель.
  Придётся самим закрывать storage CSI, CCM для LoadBalancer, обновления, сертификаты. Репозиторий
  `k8s-cloud-connectors` для этого формально есть, но **не обновлялся с 2022 года** — рискованно как
  production-зависимость.
- **Наш homelab** — третья категория: bare metal, один узел, максимум контроля и минимум денег, но нет
  managed control plane и HA. Практическая ценность MK8S для обучения — увидеть, как «managed» снимает
  именно те задачи, которые мы решаем руками (CSI, LB, IAM, апгрейды, maintenance).

### 8.3. Что из MK8S-паттернов переносимо в homelab

1. **StorageClass с `WaitForFirstConsumer`** — у YC все классы такие (топология важна); local-path у нас
   использует `WaitForFirstConsumer` по умолчанию.
2. **Явный default-класс** — в MK8S default один (`yc-network-hdd`); в homelab тоже стоит не плодить
   несколько default ([storage-classes...](./storage-classes-and-csi-provisioners.md#23-default-storageclass)).
3. **PDB перед обновлениями узлов** — YC прямо требует `PodDisruptionBudget` для безопасного drain; у нас
   на одноузловом кластере это особенно актуально при апгрейде.
4. **L7-балансировка вместо L4** — YC советует использовать Ingress/Gateway для маршрутизации, а NLB только
   для адреса; ровно наш путь Traefik → Gateway API.
5. **KMS для секретов** — в MK8S это кластерная опция; в homelab аналог — внешний secret-store
   (см. [secret-management-providers.md](../secret-management-providers.md)).

---

## 9. Не подтверждённые утверждения / оговорки

- **Точный процент SLA MK8S** — страница SLA на yandex.cloud недоступна из-за SmartCaptcha; подтверждено
  только, что SLA применяется к конфигурации с HA-master в трёх зонах.
- **CNI по умолчанию без Calico/Cilium** — в проверенных исходниках не назван. Известно только, что Cilium
  в tunnel mode = CNI, а Calico/Cilium — контроллеры сетевых политик.
- **SecurityGroup CRD** — группа `securitygroups.yandex.cloud` не найдена в доке и репозиториях YC.
  Security groups остаются объектами VPC, а не CRD.
- **Актуальные версии Helm-чартов ALB Ingress Controller / Gwin / Gateway API** — заданы переменными
  `mkt-k8s-key.*`/README и Marketplace; точные номера не подтверждены. Для ALB Ingress Controller в доке
  упоминаются `0.2.x` (чарт `0.2.9+`), в README при этом `v0.1.3` — рассинхрон, считать актуальным `0.2.9+`.
- **Точная версия CSI-драйвера в MK8S** — по публичному репо судить нельзя: последний релиз v1.2.0
  (2026-02-27), 8 звёзд; MK8S может поставлять более новую сборку.
- **Online-расширение томов** — документация заявляет online, но публичный драйвер объявляет
  `VolumeExpansion_OFFLINE`; противоречие не разрешено первоисточником.
- **Режимы доступа** — документация говорит «только ReadWriteOnce» для стандартных классов, а `VolumeCaps`
  в коде драйвера допускают ещё `MULTI_NODE_READER_ONLY`; что реально разрешено в MK8S — не проверялось на
  живом кластере.
- **Поддержка `VolumeSnapshot`** — официального подтверждения (дока/`VolumeSnapshotClass`) нет; вывод
  сделан из отсутствия snapshot-capability в production-наборе и отсутствия `csi-snapshotter` в деплое.
- **Preemptible/spot taint** — автоtaint для прерываемых нод в доке не описан; предлагается node-sitter.
- **Точные supported k8s-версии** — `presets.yaml` (1.34) и release notes (1.35 добавлен в Q1 2026)
  противоречат друг другу; проверяйте `yc managed-kubernetes list-versions`.
- **Характеристики node OS** — Ubuntu 22.04 для 1.30+; внешние узлы требуют Ubuntu 24.04 (Preview).

---

## 10. Источники

**Документация Yandex Cloud (`raw.githubusercontent.com/yandex-cloud/docs/master/...`):**
- `en/managed-kubernetes/concepts/index.md`, `network.md`, `network-policy.md`, `volume.md`, `service.md`,
  `autoscale.md`, `encryption.md`, `k8s-supported-versions.md`, `release-channels-and-updates.md`, `limits.md`,
  `usage-recommendations.md`, `external-nodes.md`, `master-configuration.md`, `kubernetes-responsibilities.md`
- `en/managed-kubernetes/operations/update-kubernetes.md`, `operations/kubernetes-cluster/*`,
  `operations/node-group/node-group-create.md`, `operations/connect/security-groups.md`,
  `operations/volumes/*`, `operations/create-load-balancer.md`, `operations/cilium.md`, `operations/calico.md`,
  `operations/apply-tf-provider.md`, `operations/apply-helm-provider.md`
- `en/managed-kubernetes/concepts/node-group/*` (`cluster-autoscaler.md`, `deploy-policy.md`, `node-drain.md`,
  `node-group-gpu.md`, `allocatable-resources.md`, `reserved-pools.md`)
- `en/managed-kubernetes/security/index.md`, `metrics.md`, `pricing.md`, `release-notes.md`, `tf-ref.md`,
  `toc.yaml`, `presets.yaml`
- `en/managed-kubernetes/alb-ref/**` (ingress-class, http-backend-group, grpc-backend-group, security-groups,
  upgrade-alb-ingress-controller, gateway-api/index, gwin-index, gwin-quickstart, gwin-policies,
  ingress-gwin-migration, http-route, grpc-route, gateway, gateway-policy, route-policy)
- `en/_includes/managed-kubernetes/**` (master-default-config, master-autoscale, managed-kube-limits,
  metrics-resources-list, metrics-k8s-tools, encrypted-storage-class-config, nrd-no-backup-note,
  note-k8s-cluster-delete, note-preemptible-vm, calico-cilium-mutual-exclusion, wlif-mk8s-description,
  wlif-mk8s-cluster-setup, master-logging-cli-description, csi-s3-actual, crossplane-provider-info,
  gateway-api-install, alb-ingress-controller-install, alb-ref/security-groups)
- `en/_includes/application-load-balancer/gateway-api/gateway-api.md`,
  `en/_includes/application-load-balancer/ingress-to-gwin-tip-with-preset.md`
- `en/_qa/managed-kubernetes/volumes.md`, `logs.md`, `general.md`

**GitHub-репозитории Yandex Cloud:**
- `yandex-cloud/yc-csi-driver` — `README.md`, `deploy/v1.0.0…v1.2.0/{driver,controller,node,rbac,storage-class}.yaml`,
  `pkg/services/constants.go`, `pkg/services/controller/controller.go`, `pkg/server/controller/controller.go`,
  `cmd/controller/{controller,config}.go`
- `yandex-cloud/yc-alb-ingress-controller` — `api/v1alpha1/*_types.go`, `api/v1alpha1/groupversion_info.go`,
  `config/crd/bases/*`, `helm/chart/README.md`, `helm/template/chart/{Chart,values}.yaml`
- `yandex-cloud/k8s-csi-s3` — `README.md`, helm index `https://yandex-cloud.github.io/k8s-csi-s3/charts/index.yaml`
- `yandex-cloud/k8s-cloud-connectors` — `README.md`
- `yandex-cloud/crossplane-provider-yc` — `README.md`
- `yandex-cloud/cert-manager-webhook-yandex` — `README.md`
- `yandex-cloud/cq-source-yc` — `README.md`
- `yandex-cloud/yc-guest-agent` — `README.md`

**GitHub REST API на 2026-09-18** (звёзды, теги, релизы, даты push) для перечисленных репозиториев,
а также `yandex-cloud/docs`.
