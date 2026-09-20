# Дистрибутивы Kubernetes: полное сравнение для homelab

Дата исследования: 2026-08-25.

## 0. Таксономия

«Дистрибутив Kubernetes» — зонтичный термин. Под ним скрываются шесть разных
классов продуктов; полезно держать их раздельно, чтобы не сравнивать k3s с OpenShift
как «конкурентов» — они решают разные задачи.

| Класс | Что это | Примеры |
|---|---|---|
| Сборка upstream | Установка «ванильного» Kubernetes из официальных пакетов/инструментов | [kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/), [Kubespray](https://kubespray.io/) |
| Лёгкие дистрибутивы | Один бинарник/snap со встроенными компонентами, single-node по умолчанию | [k3s](https://docs.k3s.io/), [k0s](https://docs.k0sproject.io/), [MicroK8s](https://microk8s.io/docs) |
| Инструменты разработки | Кластеры на ноутбуке: VM или контейнеры-в-контейнерах | [minikube](https://minikube.sigs.k8s.io/docs/), [kind](https://kind.sigs.k8s.io/), [k3d](https://k3d.io/), [colima](https://github.com/abiosoft/colima) |
| Неизменяемые ОС для кластеров | ОС, спроектированная только как хост для kubelet | [Talos Linux](https://www.talos.dev/), [Flatcar](https://www.flatcar.org/docs/latest/), Fedora CoreOS/RHCOS, [Bottlerocket](https://bottlerocket.dev/) |
| Корпоративные платформы | Коммерческие надстройки поверх кластера: UI, мультикластер, поддержка, соответствие | OpenShift/RKE2+Rancher/Tanzu/MKE/NKP/Palette/KubeSphere |
| Управляемые облака | Контрольная плата как сервис провайдера | EKS/GKE/AKS/OKE/DOKS/LKE/Yandex Cloud |

Зонтичный стандарт совместимости — программа **CNCF Certified Kubernetes Conformance**:
дистрибутив проходит официальный conformance-тест и получает право называться
«Certified Kubernetes»; на странице программы перечислено **90 сертифицированных**
конфигураций ([cncf.io/certification/software-conformance](https://www.cncf.io/certification/software-conformance/),
число меняется). Все серьёзные дистрибутивы ниже — certified, если не оговорено иное;
это значит, что навыки и манифесты переносимы между ними.

---

## 1. Лёгкие и самоуправляемые дистрибутивы

### 1.1. kubeadm — upstream-эталон

| | |
|---|---|
| Кто | SIG Cluster Lifecycle проекта Kubernetes ([док](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)) |
| Лицензия | Apache-2.0 (часть апстрима) |
| Версия | Следует версиям Kubernetes (доки на момент исследования — v1.36) |
| Минимум | **2 GB RAM на машину**, **2 CPU для control-plane** — «any less will leave little room for your apps» ([Before you begin](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#before-you-begin)) |
| Из коробки | Только bootstrap: `kubeadm init/join`, сертификаты, static pods control-plane. CNI, CRI-runtime, storage, LB, ingress — всё ставить самому ([creating a cluster](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)) |
| Фишки | Максимальная близость к апстриму; полная видимость каждого компонента; лучший способ один раз понять, из чего состоит кластер |
| Минусы | Нет ничего «из коробки»; обновления и HA собираются руками ([HA topology](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ha-topology/)) |
| Когда выбирать | Ради обучения устройству Kubernetes — собрать, изучить, снести. Как постоянный homelab-сервер — трудоёмко |

### 1.2. k3s — выбор этого хоумлаба

| | |
|---|---|
| Кто | SUSE/Rancher; CNCF-сертифицирован ([releases](https://github.com/k3s-io/k3s/releases)) |
| Лицензия | Apache-2.0 ([repo](https://github.com/k3s-io/k3s)) |
| Версия | v1.36.3+k3s1 (28 июля 2026); параллельно поддерживаются ветки 1.34–1.36 ([releases](https://github.com/k3s-io/k3s/releases)) |
| Минимум (официально) | Server: **2 core / 2 GB RAM**; Agent: **1 core / 512 MB**; SSD рекомендуется, etcd write-intensive ([requirements](https://docs.k3s.io/installation/requirements#hardware)). Для HA-режима embedded etcd — порты 2379–2380 между серверами ([там же](https://docs.k3s.io/installation/requirements#networking)) |
| Из коробки | containerd, flannel, CoreDNS, ServiceLB (klipper-lb), local-path-provisioner, Traefik v3, metrics-server, helm-controller ([packaged components](https://docs.k3s.io/installation/packaged-components)) |
| Фишки | Datastore SQLite через kine по умолчанию ([datastore](https://docs.k3s.io/datastore)); air-gap установка ([airgap](https://docs.k3s.io/installation/airgap)); ARMv7/ARM64/x86_64 ([requirements](https://docs.k3s.io/installation/requirements#architecture)); CIS-mode (`--profile=cis`, [hardening guide](https://docs.k3s.io/security/hardening-guide)); auto-deploying manifests в `/var/lib/rancher/k3s/server/manifests` |
| Минусы | Нестандартные дефолты (SQLite вместо etcd, klipper-lb); Rancher-специфика HelmChart CRD |
| Когда выбирать | Однонодовый homelab/edge; наш случай — см. раздел 7 |

### 1.3. k0s — ближайший конкурент k3s

| | |
|---|---|
| Кто | Mirantis ([k0sproject.io](https://k0sproject.io/)); LF Projects |
| Лицензия | Apache-2.0 |
| Версия | v1.36.3+k0s.2 (12 августа 2026) ([releases](https://github.com/k0sproject/k0s/releases)) |
| Минимум (официально) | Controller: **1 GB RAM / 1 vCPU**; Worker: **512 MB / 1 vCPU**; диск: ~0.5 GB (controller) / ~1.6 GB (worker) минимум ([system requirements](https://docs.k0sproject.io/stable/system-requirements/)). Замер проекта: пустой контроллер ест ~510 MB ([замеры](https://docs.k0sproject.io/stable/system-requirements/#controller-node-measured-memory-consumption)) |
| Из коробки | containerd, kube-router (CNI по умолчанию, есть Calico), Konnectivity, manifest deployer, встроенный helm-менеджер ([architecture](https://docs.k0sproject.io/stable/architecture/)) |
| Фишки | Autopilot — автообновления узлов ([autopilot](https://docs.k0sproject.io/stable/autopilot/)); node-local load balancing; airgap-установка; Windows workers (экспериментально); экосистема k0rdent от Mirantis для мультикластера ([product updates](https://www.mirantis.com/product-updates/)) |
| Минусы | Нет LB из коробки (MetalLB ставится отдельно, [пример](https://docs.k0sproject.io/stable/examples/metallb-loadbalancer/)); нет ingress/storage provisioner из коробки; сообщество меньше k3s |
| Когда выбирать | Если хочется «k3s, но чище от Rancher-специфики» и важны автообновления узлов |

### 1.4. MicroK8s — snap-подход Canonical

| | |
|---|---|
| Кто | Canonical ([canonical.com/microk8s](https://canonical.com/microk8s/docs)) |
| Лицензия | Apache-2.0 |
| Версия | Трек 1.36 (релиз 25 мая 2026) ([releases](https://github.com/canonical/microk8s/releases)) |
| Минимум (официально) | «runs in as little as **540 MB** of memory», рекомендация: **4 GB RAM / 20 GB disk** ([get started](https://canonical.com/microk8s/docs/getting-started)) |
| Из коробки | Почти ничего: минимальное ядро + система **add-ons** (`microk8s enable dns hostpath-storage metrics-server ingress …`) ([addons](https://microk8s.io/docs/addons)) |
| Фишки | Кластеризация командой `microk8s join` (HA из трёх нод); каналы snap = простые обновления; Ubuntu Pro-поддержка; 12-летние LTS-обязательства Canonical по K8s ([блог](https://canonical.com/blog/tag/charmed-kubernetes)) |
| Минусы | **Только snap**: на Fedora Server придётся ставить snapd — чуждая пакетная модель для нашего хоста; обновления snap'а менее контролируемы |
| Когда выбирать | На Ubuntu-хостах; на Fedora — k3s удобнее |

### 1.5–1.7. Инструменты разработки: minikube, kind, k3d

| | minikube | kind | k3d |
|---|---|---|---|
| Кто | CNCF SIG project | Kubernetes SIG project | Community |
| Версия | v1.38.1 (19 фев 2026) ([releases](https://github.com/kubernetes/minikube/releases)) | v0.32.0 (2 июн 2026) ([releases](https://github.com/kubernetes-sigs/kind/releases)) | v5.9.0 (2 июн 2026) ([releases](https://github.com/k3d-io/k3d/releases)) |
| Минимум (официально) | **2 CPU / 2 GB free mem / 20 GB disk** ([start docs](https://minikube.sigs.k8s.io/docs/start/)) | Зависит от Docker-хоста; каждый node = контейнер ([basics](https://kind.sigs.k8s.io/docs/user/quick-start/)) | То же: k3s внутри Docker ([k3d.io](https://k3d.io/)) |
| Как работает | VM или контейнер (Docker/QEMU/KVM/Hyper-V…) | Контейнеры-в-контейнерах без systemd | Обёртка над k3s-образами в Docker |
| Фишки | Драйверы, addons, multi-node, dashboard | Быстрый старт/удаление — стандарт CI | Самый быстрый способ поднять throwaway k3s-кластер |
| Для homelab-сервера | Не подходит (это инструмент ноутбука) | Не подходит | Годится для локальных экспериментов рядом с рабочей станцией |

### 1.8. Kubespray — production-инсталлятор

Ansible-набор плейбуков, разворачивающий «ванильный» кластер на ваших хостах:
CNCF **incubating** проект ([landscape](https://landscape.cncf.io/)), актуальная версия
v2.31.0 (25 апреля 2026) ([releases](https://github.com/kubernetes-sigs/kubespray/releases)).
Поддерживает HA control-plane, разные CNI, офлайн-установку. Минус для нас: это
инсталлятор, а не дистрибутив — нужен запас хостов и знание Ansible; на одной машине
избыточен.

### 1.9. Typhoon — нишевый, но живой

Бесплатные Terraform-модули для bare-metal/Fedora CoreOS/AWS-кластеров от Poseidon.
Проверено: проект активен — релиз **v1.36.1 от 8 июня 2026** ([releases](https://github.com/poseidon/typhoon/releases)).
Фишка — кластеры на неизменяемых CoreOS-подобных ОС, декларативно через Terraform.
Минус: нет поддержки, мало документации «для людей», требует связки terraform+FCOS.
Интересен как источник идей, не как основной путь.

### 1.10. k3OS — устарел

ОС-проект Rancher «Kubernetes as OS» **архивирован**: репозиторий
[rancher/k3os](https://github.com/rancher/k3os) помечен `archived: true`, последний
пуш — декабрь 2023 (проверено GitHub API). Идея «минимальной неизменяемой ОС с
k3s» эволюционировала в Talos-подобные проекты. Не рассматривать для новых установок.

### 1.11. colima — не дистрибутив, но частый сосед

[Colima](https://github.com/abiosoft/colima) (v0.10.3, 4 июня 2026, [releases](https://github.com/abiosoft/colima/releases)) —
менеджер containerd/Docker-рантаймов для macOS/Linux с опциональным встроенным
Kubernetes (k3s внутри VM). Упомянут в таксономии потому, что его часто путают с
дистрибутивами: это инструмент ноутбука («container runtime with minimal setup»),
не вариант для сервера; полезен только как локальная песочница рядом с основной
рабочей машиной.

---

## 2. Неизменяемые ОС-платформы

Отдельный класс: ОС, у которых единственная задача — безопасно запускать kubelet.
Корневая ФС read-only, обновления атомарной заменой образа, конфигурация декларативна.

| ОС | Кто/лицензия | Статус (авг 2026) | Фишки |
|---|---|---|---|
| **Talos Linux** | Sidero Labs, MPL-2.0 ([repo](https://github.com/siderolabs/talos)) | Активен: стабильная ветка v1.13 (релизы с апреля 2026), v1.14 в RC (авг 2026) ([releases](https://github.com/siderolabs/talos/releases)) | Нет SSH, shell и пакетного менеджера — всё через gRPC-API (`talosctl`) с mTLS; <50 бинарников, ~80–100 MB ОС ([siderolabs.com/talos-linux](https://www.siderolabs.com/talos-linux)); A/B-обновления с автооткатом; встроенные flannel/etcd/kubelet |
| **Flatcar Container Linux** | Наследник Kinvolk (куплена Microsoft в 2021), развивается открыто, Apache-2.0 ([repo](https://github.com/flatcar/Flatcar), пуш 21 авг 2026) | Активен; входит в списки тестирования k0s ([system requirements](https://docs.k0sproject.io/stable/system-requirements/)) | Контейнерный Linux в духе CoreOS: OSTree-обновления, Ignition-provisioning; нейтрален к дистрибутиву k8s |
| **Fedora CoreOS / RHCOS / SCOS** | Red Hat | FCOS — upstream автoобновляемая minimal-ОС ([fedora coreos](https://docs.fedoraproject.org/en-US/fedora-coreos/)); RHCOS — вариант для OpenShift; OKD перешла на CentOS Stream CoreOS ([okd blog](https://okd.io/blog/)) | База Red Hat-экосистемы; вне OpenShift используется редко |
| **Bottlerocket** | AWS, open source ([repo](https://github.com/bottlerocket-os/bottlerocket)) | Активен: v1.64.0 (29 июля 2026) ([releases](https://github.com/bottlerocket-os/bottlerocket/releases)) | Минимальная ОС для контейнерных ворклоадов EKS/ECS; два корневых раздела, admin/control-контейнеры вместо shell |

Минимумы Talos (официально): Control plane **2 GiB RAM / 2 cores / 10 GiB disk**,
Worker **1 GiB / 1 core / 10 GiB**; рекомендуемое — вдвое больше ([system requirements](https://docs.siderolabs.com/talos/v1.13/getting-started/system-requirements)).
Минус класса: нет привычного администрирования хоста (пакеты, sshd, docker CLI) —
всё, что раньше делалось на хосте, должно жить в кластере или system extensions.

---

## 3. Корпоративные платформы (коммерческие и их open-source апстримы)

### 3.1. Red Hat OpenShift и его апстрим OKD

Важно различать два продукта:

| | **OpenShift Container Platform (OCP)** | **OKD** |
|---|---|---|
| Модель | Коммерческая подписка Red Hat (core-pair/node subscriptions, [subscription guide](https://www.redhat.com/en/resources/self-managed-openshift-subscription-guide)) | Бесплатная community-версия, Apache-2.0 ([repo](https://github.com/okd-project/okd)) |
| Версия | Доки до 4.22 ([docs.redhat.com](https://docs.redhat.com/en/documentation/openshift_container_platform/4.14/html/installing_on_a_single_node/install-sno-installing-sno)) | 4.22.0-okd-scos.8 (20 авг 2026), Kubernetes 1.36; ведутся сборки 5.0 EC ([releases](https://github.com/okd-project/okd/releases)) |
| Базовая ОС | RHCOS | CentOS Stream CoreOS (SCOS), ранее FCOS ([okd blog](https://okd.io/blog/)) |
| Минимум Single-Node (официально) | **8 vCPU / 16 GB RAM / 120 GB** ([installing on a single node](https://docs.redhat.com/en/documentation/openshift_container_platform/4.10/html/installing/installing-on-a-single-node); та же цифра в статье Red Hat про bare-metal SNO) | **4 vCPU / 120 GB** с явным предупреждением о рисках деградации ([docs.okd.io SNO](https://docs.okd.io/latest/installing/installing_sno/install-sno-installing-sno.html)); RAM в таблице минимума не указана явно — реалистично ≥16 GB |

Общие фишки семейства: Routes (альтернатива Ingress), встроенный image registry,
web-console, операторы как механизм установки всего, Security Context Constraints
(вместо Pod Security Standards), интегрированный CI/CD (Tekton), EUS-релизы.
Минусы для homelab: ресурсоёмкость (SNO съедает почти всю машину ещё до приложений),
сложность эксплуатации и обязательность их ОС (SCOS/RHCOS).

### 3.2. RKE2 + Rancher Manager (SUSE)

| | |
|---|---|
| Лицензии | RKE2 — открытый (Apache-2.0, [repo](https://github.com/rancher/rke2)); Rancher Prime — коммерческая подписка SUSE |
| Версии | RKE2 v1.36.3+rke2r1 (4 августа 2026, [releases](https://github.com/rancher/rke2/releases)); Rancher Manager v2.15.0 (30 июля 2026, [releases](https://github.com/rancher/rancher/releases)) |
| Позиционирование | «Безопасный enterprise-Kubernetes»: дефолты по CIS Benchmark, FIPS-совместимые сборки, SELinux, audit-логи ([hardening guide](https://docs.rke2.io/security/hardening_guide)) |
| Связь с k3s | Одна команда SUSE/Rancher: k3s — edge/лёгкий сценарий, RKE2 — «полноценный» hardened-дистрибутив с теми же helm-controller/local-path компонентами |
| Rancher Manager | Мульти-кластерный UI/API: управление десятками кластеров (в т.ч. EKS/AKS/GKE), каталог приложений; тяжёлый для одного узла |

### 3.3. Mirantis Kubernetes Engine (MKE)

Коммерческая платформа Mirantis (купившей Docker Enterprise в 2019): текущие ветки
MKE 3.8/3.9 получают патчи (3.9.5 и 3.8.15 — 4 августа 2026, [product updates](https://www.mirantis.com/product-updates/)),
параллельно развивается MKE 4 ([docs](https://mirantis.github.io/mke-docs/docs/release-notes/)).
Включает Mirantis Container Runtime и Secure Registry; лицензирование — подписка
Mirantis Enterprise. Для homelab неприменима коммерчески; k0s — её открытая основа.

### 3.4. VMware Tanzu (Broadcom)

После поглощения VMware Broadcom портфель перестроен: старые SKU Tanzu сняты с
продажи 6 мая 2024 ([End of Availability notice](https://knowledge.broadcom.com/external/article/368947/end-of-availability-notification-for-exi.html)),
Tanzu Community Edition закрыт — вместо него бесплатная загрузка Tanzu Kubernetes Grid
([README community-edition](https://github.com/vmware-tanzu/community-edition)).
Теперь Kubernetes-runtime продаётся только в составе подписок VMware Cloud Foundation /
vSphere Foundation, тарификация за ядра; TKr переименованы в VKr ([Broadcom KB](https://knowledge.broadcom.com/external/article/397456/the-vmware-vsphere-kubernetes-releases-v.html)).
Для homelab без vSphere — нерелевантно.

### 3.5. Nutanix Kubernetes Platform (NKP, ex-D2iQ DKP)

D2iQ куплена Nutanix в январе 2024 ([анонс](https://www.nutanix.com/blog/acquisition-of-d2iq-platform));
Distributed Kubernetes Platform (DKP) стала NKP ([nutanix.com/d2iq](https://www.nutanix.com/d2iq)) —
коммерческая платформа управления кластерами поверх гиперконвергентной инфраструктуры
Nutanix. Продукт живёт, но вне экосистемы Nutanix смысла не имеет.

### 3.6. KubeSphere

Открытая (Apache-2.0) надстройка управления поверх любого кластера, происхождение —
QingCloud (Китай). Проверено: репозиторий жив (пуш июль 2026, ~17k ⭐), но релизный
ритм замедлился — последняя версия v4.1.3 вышла 24 марта 2025 ([releases](https://github.com/kubesphere/kubesphere/releases)).
Фишки: мультитенантный web-UI, DevOps-пайплайны, app store. Риски: зависимость от
одного корпоративного спонсора, редкие релизы — для долгосрочного homelab сомнительно.

### 3.7. Spectro Cloud Palette

Коммерческая платформа управления «полным стеком» Kubernetes (свои дистрибутивы
PXK/PXK-E для edge + управление EKS/RKE2/k3s-кластерами), лидер open-source проекта
[Kairos](https://kairos.io/) (неизменяемая edge-ОС). Проверено: компания независима —
в июле 2026 привлекла раунд Series D $100M ([новости](https://www.spectrocloud.com/news)),
в январе 2026 анонсировала собственную immutable-ОС Hadron. Чисто enterprise: цена
по запросу, для homelab — только как любопытный ландшафтный факт.

### 3.8. Charmed Kubernetes (Canonical)

Открытый дистрибутив на Juju-charms (операторах Canonical): каждый компонент
(kubeapi, etcd, CNI) — charm с lifecycle-автоматизацией. Открытый код, монетизация —
Ubuntu Pro-поддержка; Canonical заявляет 12-летний горизонт сопровождения Kubernetes
LTS ([блог](https://canonical.com/blog/tag/charmed-kubernetes)). Параллельно Canonical
развивает новый дистрибутив «Canonical Kubernetes» (snap-based, beta с марта 2024).
Экзотичен вне Ubuntu-мира; на Fedora — лишние зависимости.

### 3.9. Кратко об остальном ландшафте

| Проект | Что это | Почему не дистрибутив в нашем смысле |
|---|---|---|
| [Gardener](https://gardener.cloud/) (SAP) | Управление фермами кластеров («shoot» clusters) поверх IaaS | Это control-plane-farm менеджер, а не сборка k8s для одной машины |
| [Sealos](https://github.com/labring/sealos) | «Cloud OS»: installer + PaaS поверх kubeadm-кластеров | Инсталлятор/обвязка |
| [KubeKey](https://github.com/kubesphere/kubekey) | Установщик кластеров (от команды KubeSphere) | Инсталлятор |
| [Loft Labs vcluster](https://www.vcluster.com/) | Виртуальные кластеры внутри кластера | Дополнение, не дистрибутив |

---

## 4. Управляемые облачные (для полноты картины)

Для локального homelab без внешнего доступа этот класс неприменим: контрольная плата
живёт у провайдера, нужен интернет и оплата. Приведены для ориентира.

| Провайдер | Продукт | Примечание |
|---|---|---|
| Amazon | [EKS](https://aws.amazon.com/eks/) | Плата за control-plane почасово; Bottlerocket-ноды |
| Google | [GKE](https://cloud.google.com/kubernetes-engine) | Автопилот/Standard; самые «ранние» версии k8s |
| Microsoft | [AKS](https://azure.microsoft.com/products/aks) | Бесплатный control-plane, платят за ноды |
| Oracle / DigitalOcean / Linode | [OKE](https://www.oracle.com/cloud/cloud-native/container-engine-kubernetes/) / [DOKS](https://www.digitalocean.com/products/managed-kubernetes) / LKE | Дешёвые управляемые варианты |
| Российские | Yandex Cloud Managed Service for Kubernetes, VK Cloud | Те же ограничения: облако, интернет, рублёвая подписка; данные покидают дом |

Вывод: не подходят принципиально — сервисы должны работать при выключенном
интернете, данные остаются дома.

---

## 5. Сводная таблица минимальных ресурсов

Цифры — **официальные минимумы из документации проектов** (если не помечено иначе);
«комфорт» — оценка для запуска нескольких реальных сервисов, а не пустого кластера.

| Дистрибутив | vCPU (min) | RAM (min) | Disk (min) | Single-node viability | HA-вариант |
|---|---|---|---|---|---|
| kubeadm | 2 (control-plane) | 2 GB | — | да, вручную | stacked/external etcd, вручную ([dok](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ha-topology/)) |
| k3s | 2 (server) | 2 GB | SSD рекомендован | да, из коробки (SQLite) | embedded etcd / внешний DB ([datastore](https://docs.k3s.io/datastore)) |
| k0s | 1 (controller) | 1 GB | ~0.5 GB | да (controller+worker 1GB/1vCPU) | etcd из коробки ([requirements](https://docs.k0sproject.io/stable/system-requirements/)) |
| MicroK8s | — (не нормируется) | 540 MB (рек. 4 GB) | рек. 20 GB | да | `microk8s join` ×3 ([get started](https://canonical.com/microk8s/docs/getting-started)) |
| minikube | 2 | 2 GB free | 20 GB free | да (это его суть) | нет ([docs](https://minikube.sigs.k8s.io/docs/start/)) |
| kind | зависит от Docker-хоста | то же | то же | да (контейнер) | multi-node контейнеры |
| k3d | как k3s | как k3s | как Docker-хост | да | multi-server флагом |
| Talos | 2 (CP) / 1 (worker) | 2 GiB / 1 GiB | 10 GiB | да (control-plane с worker-ролью) | 3×control-plane etcd ([requirements](https://docs.siderolabs.com/talos/v1.13/getting-started/system-requirements)) |
| OKD SNO | 4 ⚠️ | ≥16 GB (не указано явно) | 120 GB | да, но впритык ([dok](https://docs.okd.io/latest/installing/installing_sno/install-sno-installing-sno.html)) | 3×control-plane: 4 vCPU/100 GB каждый ([там же](https://docs.okd.io/latest/installing/installing_sno/install-sno-installing-sno.html)) |
| OpenShift SNO | **8** | **16 GB** | **120 GB** | да, официально ([dok](https://docs.redhat.com/en/documentation/openshift_container_platform/4.10/html/installing/installing-on-a-single-node)) | 3 CP + 2 worker минимум |

Наблюдения: разброс «минимальной памяти» — от 540 MB (MicroK8s) до 16 GB (OpenShift
SNO) — тридцатикратный при одном и том же Kubernetes API. Разница целиком во
встроенных компонентах и накладных расходах платформенных сервисов.

Два предостережения при чтении цифр:

1. «Минимум» проектов почти всегда означает пустой кластер без рабочих нагрузок:
   k0s честно публикует замеры роста памяти от числа подов (~510 MB → ~1 GB при 100
   подах, [system requirements](https://docs.k0sproject.io/stable/system-requirements/#controller-node-measured-memory-consumption)),
   у остальных рост не документирован и проверяется только на практике.
2. Для ~30 сервисов этого homelab решает не минимум дистрибутива, а суммарный бюджет
   хоста: к требованиям control-plane добавляются requests/limits всех приложений
   (см. раздел 6.11 в [docker-compose-to-kubernetes-migration.md](./docker-compose-to-kubernetes-migration.md)).

---

## 6. Сводная матрица «фишек»

Легенда: ✅ встроено по умолчанию; 🔧 включается штатным механизмом (add-on/chart);
❌ отсутствует; «—» не проверялось в этом исследовании. Колонка FIPS убрана:
страницы с FIPS-требованиями у ряда проектов не открылись при проверке — утверждения
не подтверждены первоисточниками в этой сессии.

| Возможность | k3s | k0s | MicroK8s | kubeadm | Talos | RKE2 | OKD/OCP |
|---|---|---|---|---|---|---|---|
| Ingress-контроллер | ✅ Traefik v3 | ❌ | 🔧 addon | ❌ | ❌ (ставится chart'ом) | ✅ ingress-nginx ([dok](https://docs.rke2.io/)) | ✅ Router (HAProxy) |
| LoadBalancer | ✅ ServiceLB | ❌ (MetalLB 🔧) | 🔧 addon (MetalLB) | ❌ | ❌ (MetalLB 🔧) | ❌ (ServiceLB опц.) | ✅ (в облаке) |
| Storage provisioner | ✅ local-path | ❌ (Longhorn/OpenEBS 🔧) | 🔧 hostpath-storage | ❌ | ❌ (Longhorn 🔧) | ✅ local-path | ✅ (CSI-операторы) |
| Helm-интеграция | ✅ helm-controller | ✅ ([helm charts](https://docs.k0sproject.io/stable/helm-charts/)) | ❌ (helm ставится вручную) | ❌ | 🔧 (chart-репо Flux/Argo) | ✅ helm-controller | ✅ Operators |
| Auto-deploy манифестов из каталога | ✅ ([manifests](https://docs.k3s.io/installation/packaged-components)) | ✅ ([manifest deployer](https://docs.k0sproject.io/stable/manifests/)) | ❌ | ❌ (static pods only) | ❌ | ✅ | ❌ (Operators) |
| Web UI | ❌ | ❌ | 🔧 dashboard addon | ❌ | ❌ (+ Omni 💰) | 🔧 Rancher | ✅ консоль |
| Multi-node clustering | ✅ agent/server | ✅ k0sctl | ✅ join | ✅ join | ✅ | ✅ | ✅ |
| ARM (arm64/armhf) | ✅ armhf/arm64 | ✅ armv7/aarch64 | ✅ | ✅ (kubelet arm) | ✅ aarch64/armv7 | ✅ arm64 | частично |
| Air-gap установка | ✅ ([dok](https://docs.k3s.io/installation/airgap)) | ✅ ([dok](https://docs.k0sproject.io/stable/airgap-install/)) | 🔧 offline deploy | 🔧 (локальный registry) | ✅ (image bundle) | ✅ | ✅ (mirror registry) |
| CIS-hardened профиль | 🔧 `--profile=cis` ([guide](https://docs.k3s.io/security/hardening-guide)) | 🔧 ([kube-bench](https://docs.k0sproject.io/stable/cis_benchmark/)) | ❌ | ❌ | ✅ (безопасность by design) | ✅ по умолчанию ([guide](https://docs.rke2.io/security/hardening_guide)) | ✅ compliance-режимы |
| Автообновление узлов | ❌ (system-upgrade-controller отдельно) | ✅ autopilot | ✅ snap refresh | ❌ | ✅ A/B-образы | 🔐 (через Rancher) | ✅ (EUS/OCM) |
| GitOps-нативность | 🔧 любой CD | 🔧 (Flux-пример в доках) | 🔧 | 🔧 | ✅ (машинный конфиг = YAML в git) | 🔧 Fleet (Rancher) | 🔧 Argo/ACS |

---

## 7. Рекомендация для этого хоумлаба

Контекст: Fedora Server 44, одна машина `<node1-ip>`, цель — обучение, ручной
подход (`kubectl apply`), параллельная жизнь с Docker Compose (см.
[docker-compose-to-kubernetes-migration.md](./docker-compose-to-kubernetes-migration.md)).

| Вариант | Вердикт | Почему |
|---|---|---|
| **k3s** | ✅ подтверждаем | Единственный класс «лёгкий дистрибутив», который: (а) официально поддерживает RHEL/Fedora-семейство ([requirements](https://docs.k3s.io/installation/requirements#operating-systems)), (б) ставится одним скриптом без snap, (в) даёт из коробки ingress/LB/storage/Helm — весь стек, который мы мигрируем; 2 core/2 GB минимума легко помещаются в бюджет сервера рядом с Compose |
| k0s | запасной | Чуть легче формально (1 GB контроллер), но нет LB/ingress/storage из коробки — больше ручной работы без учебной ценности; выбрали бы его при аллергии на Rancher-специфику |
| MicroK8s | нет | Snap-only — чужеродно на Fedora |
| kubeadm | разово, ради теории | Ценность — один вечер «собрать кластер руками и понять анатомию», потом снести; как постоянная платформа — лишняя работа |
| Talos | план на вторую ноду | Если появится mini-PC: неизменяемая API-управляемая ОС идеально ложится на GitOps-модель; но на текущем сервере с Docker Compose рядом — несовместимо (Talos = вся машина) |
| OKD / OpenShift | нет | SNO-минимумы (4–8 vCPU, 120 GB, SCOS-only) съедают сервер целиком ради платформенных сервисов, которые в homelab не нужны |
| RKE2+Rancher, MKE, NKP, Tanzu, Palette | нет | Enterprise-модель: подписки, мульти-кластер, требования железа и лицензий не для одной домашней машины |
| Управляемые облака | нет | Интернет-зависимость и вынос данных из дома противоречат самой идее homelab |

Итог: k3s остаётся правильным первым шагом; Talos — главный кандидат на «вторую главу»
при появлении второго устройства; всё остальное ландшафта полезно знать, чтобы
осознанно не выбирать.

### 7.1. Пять вопросов для выбора дистрибутива (шпаргалка)

| Вопрос | Если ответ «да» |
|---|---|
| Кластер живёт на ноутбуке или в CI? | minikube / kind / k3d, не серверные дистрибутивы |
| Одна машина, мало RAM, нужен весь стек из коробки? | k3s (наш случай) или MicroK8s (если Ubuntu/snap приемлем) |
| Несколько нод и CIS-комплаенс? | RKE2 (+Rancher Manager для UI) или k0s с autopilot |
| Хост = «черный ящик», всё через Git? | Talos Linux — ОС как часть GitOps-стека |
| Нужны поддержка/лицензии для компании? | OpenShift/Rancher Prime/NKP/Palette — вопрос бюджета, не техники |

---

## Не подтверждённые утверждения / оговорки

- **RAM-минимум OKD SNO** — в таблице требований OKD указаны 4 vCPU и 120 GB диска,
  память явно не названа; оценка «реалистично ≥16 GB» следует из OCP-таблицы (16 GB)
  и предупреждения OKD о нехватке headroom.
- **FIPS-поддержка** отдельных дистрибутивов не включена в матрицу: прямые страницы
  документации не открылись при проверке (404), утверждения без первоисточника
  опущены намеренно.
- **История Kinvolk→Microsoft** для Flatcar — общеизвестный факт 2021 года, но в этой
  сессии подтверждалась косвенно (упоминание «by Kinvolk» в доках k0s, активный
  независимый репозиторий flatcar/Flatcar).
- **KubeSphere**: медленный релизный цикл (v4.1.3, март 2025) — констатация факта по
  releases; причины (финансирование и пр.) — не проверялись и здесь не утверждаются.
- Точное число Certified Kubernetes продуктов меняется; «90» снято со страницы CNCF
  2026-08-25.

## Источники

### Апстрим и лёгкие дистрибутивы

- [kubernetes.io — Installing kubeadm (требования)](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/) · [HA Topology](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ha-topology/)
- [docs.k3s.io — Requirements](https://docs.k3s.io/installation/requirements) · [Datastore](https://docs.k3s.io/datastore) · [Packaged Components](https://docs.k3s.io/installation/packaged-components) · [Air-Gap](https://docs.k3s.io/installation/airgap) · [Hardening Guide](https://docs.k3s.io/security/hardening-guide) · [Releases](https://github.com/k3s-io/k3s/releases)
- [docs.k0sproject.io — System Requirements](https://docs.k0sproject.io/stable/system-requirements/) · [Autopilot](https://docs.k0sproject.io/stable/autopilot/) · [Releases](https://github.com/k0sproject/k0s/releases)
- [MicroK8s — Get Started (540 MB)](https://canonical.com/microk8s/docs/getting-started) · [Docs home](https://microk8s.io/docs) · [Releases](https://github.com/canonical/microk8s/releases)
- [minikube — Start (требования)](https://minikube.sigs.k8s.io/docs/start/) · [Releases](https://github.com/kubernetes/minikube/releases)
- [kind — Quick Start](https://kind.sigs.k8s.io/docs/user/quick-start/) · [Releases](https://github.com/kubernetes-sigs/kind/releases)
- [k3d](https://k3d.io/) · [Releases](https://github.com/k3d-io/k3d/releases)
- [Kubespray](https://kubespray.io/) · [Releases](https://github.com/kubernetes-sigs/kubespray/releases)
- [Poseidon Typhoon — Releases](https://github.com/poseidon/typhoon/releases) (v1.36.1, июнь 2026)
- [rancher/k3os — архивный репозиторий](https://github.com/rancher/k3os)

### Неизменяемые ОС

- [Talos Linux — System Requirements](https://docs.siderolabs.com/talos/v1.13/getting-started/system-requirements) · [ siderolabs.com/talos-linux ](https://www.siderolabs.com/talos-linux) · [Releases](https://github.com/siderolabs/talos/releases)
- [Flatcar — репозиторий](https://github.com/flatcar/Flatcar) · [flatcar.org docs](https://www.flatcar.org/docs/latest/)
- [Fedora CoreOS](https://docs.fedoraproject.org/en-US/fedora-coreos/) · [OKD blog: переход на SCOS](https://okd.io/blog/)
- [Bottlerocket](https://bottlerocket.dev/) · [Releases](https://github.com/bottlerocket-os/bottlerocket/releases)

### Корпоративные платформы

- [Red Hat: Installing on a single node (SNO-минимумы)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.10/html/installing/installing-on-a-single-node) · [How to install SNO on bare metal (8 vCPU/16 GB/120 GB)](https://developers.redhat.com/articles/2024/04/29/how-install-single-node-openshift-bare-metal) · [Subscription Guide](https://www.redhat.com/en/resources/self-managed-openshift-subscription-guide)
- [OKD — Installing on a single node](https://docs.okd.io/latest/installing/installing_sno/install-sno-installing-sno.html) · [okd-project/okd releases](https://github.com/okd-project/okd/releases) · [okd.io/blog](https://okd.io/blog/)
- [RKE2 — Hardening Guide](https://docs.rke2.io/security/hardening_guide) · [Releases](https://github.com/rancher/rke2/releases) · [Rancher Releases](https://github.com/rancher/rancher/releases)
- [Mirantis Product Updates (MKE 3.9.x/4)](https://www.mirantis.com/product-updates/) · [MKE 4 docs](https://mirantis.github.io/mke-docs/docs/release-notes/)
- [Broadcom: End of Availability Tanzu SKUs](https://knowledge.broadcom.com/external/article/368947/end-of-availability-notification-for-exi.html) · [VKr lifecycle](https://knowledge.broadcom.com/external/article/397456/the-vmware-vsphere-kubernetes-releases-v.html) · [vmware-tanzu/community-edition (закрыт)](https://github.com/vmware-tanzu/community-edition)
- [Nutanix: acquisition of D2iQ](https://www.nutanix.com/blog/acquisition-of-d2iq-platform) · [nutanix.com/d2iq → NKP](https://www.nutanix.com/d2iq)
- [KubeSphere releases](https://github.com/kubesphere/kubesphere/releases)
- [Spectro Cloud news (Series D, Hadron)](https://www.spectrocloud.com/news) · [Kairos](https://kairos.io/)
- [Charmed Kubernetes](https://ubuntu.com/kubernetes/charmed-k8s) · [Canonical blog tag](https://canonical.com/blog/tag/charmed-kubernetes)
- [Gardener](https://gardener.cloud/) · [Sealos](https://github.com/labring/sealos) · [KubeKey](https://github.com/kubesphere/kubekey) · [vcluster](https://www.vcluster.com/)

### Управляемые и прочее

- [AWS EKS](https://aws.amazon.com/eks/) · [Google GKE](https://cloud.google.com/kubernetes-engine) · [Azure AKS](https://azure.microsoft.com/products/aks) · [Oracle OKE](https://www.oracle.com/cloud/cloud-native/container-engine-kubernetes/) · [DigitalOcean DOKS](https://www.digitalocean.com/products/managed-kubernetes)
- [CNCF Certified Kubernetes Conformance](https://www.cncf.io/certification/software-conformance/)

### Внутри репозитория

- [docker-compose-to-kubernetes-migration.md](./docker-compose-to-kubernetes-migration.md) · [argo-cd-vs-flux-cd.md](./argo-cd-vs-flux-cd.md)
