# CNI-решения для Kubernetes: от спецификации до выбора для homelab на k0s

> Sources: официальные доки — спецификация CNI (github.com/containernetworking/cni), kubernetes.io,
> docs.k0sproject.io, docs.k3s.io, docs.rke2.io, microk8s.io, docs.openshift.com, docs.aws.amazon.com,
> learn.microsoft.com, cloud.google.com, docs.oracle.com, docs.digitalocean.com, techdocs.akamai.com,
> docs.hetzner.com (был недоступен на момент исследования), www.civo.com; доки проектов — docs.cilium.io,
> docs.tigera.io (Calico), github README (flannel, kube-router, antrea, multus, ovn-kubernetes, weaveworks/weave);
> отчёты CNCF (Annual Survey 2024, Cilium Project Journey Report); данные GitHub API на 12.09.2026.

Дата исследования: 2026-09-12. Актуальная ветка Kubernetes — v1.37, k3s/RKE2 стабильная ветка — v1.36.

Смежные исследования: [k3s-vs-k0s-detailed-comparison.md](./k3s-vs-k0s-detailed-comparison.md),
[kubernetes-distributions-comparison.md](./kubernetes-distributions-comparison.md),
[docker-compose-to-kubernetes-migration.md](./docker-compose-to-kubernetes-migration.md),
[remote-access-metallb-solutions.md](./remote-access-metallb-solutions.md) (MetalLB L2 + Tailscale).

---

## 1. Что такое CNI

### 1.1. Терминология и место CNI

CNI (Container Network Interface) — это **спецификация** и набор соглашений о том, как контейнерный
рантайм должен подключать контейнер к сети. Спецификация определяет пять вещей ([SPEC.md](https://github.com/containernetworking/cni/blob/main/SPEC.md)):

1. формат сетевой конфигурации (JSON);
2. протокол, по которому рантайм вызывает плагины;
3. процедуру выполнения цепочки плагинов по конфигурации;
4. процедуру делегирования функциональности (например, IPAM) другим плагинам;
5. типы данных результата, которые плагин возвращает рантайму.

Текущая версия спецификации — **1.1.0** (тег `spec-v1.0.0` отменил не-list-конфигурации и ввёл v1.0.0; далее 1.1.0).
Исторические версии: v0.1.0 → v0.2.0 (команда `VERSION`) → v0.3.0 (цепочки плагинов, богатый тип результата) →
v0.3.1 → v0.4.0 (команда `CHECK`, `prevResult` на `DEL`) → v1.0.0 → 1.1.0.

### 1.2. Ключевые понятия спецификации

| Термин | Смысл |
|---|---|
| **container** | «домен изоляции сети»: network namespace Linux или VM — технология не оговаривается |
| **network** | группа уникально адресуемых endpoint'ов, которые могут общаться друг с другом |
| **runtime** | программа, исполняющая CNI-плагины (в Kubernetes это CRI-рантайм: containerd, CRI-O) |
| **plugin** | исполняемый файл, который применяет сетевую конфигурацию к контейнеру |
| **CNI_COMMAND** | операция: `ADD`, `DEL`, `CHECK`, `GC`, `STATUS`, `VERSION` |
| **IPAM plugin** | делегированный плагин для управления IP-адресами (host-local, dhcp, Whereabouts) |

Плагины делятся на «интерфейсные» (создают интерфейс в контейнере и дают связность — например `bridge`) и
«цепочные» (модифицируют уже созданный интерфейс — `tuning`, `portmap`, `bandwidth`). Конфигурация — это
JSON-список объектов с полем `type` (имя бинарника) и опциональными `ipam`, `dns`, `capabilities`.
Рантайм передаёт параметры через переменные окружения (`CNI_CONTAINERID`, `CNI_NETNS`, `CNI_IFNAME`,
`CNI_PATH`, `CNI_ARGS`), конфигурацию — через stdin, результат — JSON на stdout ([SPEC.md §2](https://github.com/containernetworking/cni/blob/main/SPEC.md)).

**Цепочка плагинов (plugin chaining).** При `ADD` плагины выполняются по порядку списка `plugins`, и результат
предыдущего передаётся следующему как `prevResult`. При `DEL` — в обратном порядке. Это позволяет собирать
сеть из кирпичиков: например `bridge` (интерфейс) → `tuning` (sysctl) → `portmap` (hostPort). Именно так
выглядит конфигурация сети пода у Calico, где первым идёт `calico`, а затем `portmap` и/или `bandwidth`
([пример в доке Kubernetes](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/)).

### 1.3. Как kubelet и CRI вызывают CNI

**Важный сдвиг:** до Kubernetes 1.24 управлением CNI занимался сам kubelet (флаги `--cni-bin-dir` и
`--network-plugin`). Начиная с **Kubernetes 1.24** эти параметры удалены: теперь за загрузку CNI-плагинов
отвечает **контейнерный рантайм** (containerd/CRI-O), а kubelet только просит рантайм создать sandbox-под
с сетью ([Network Plugins | Kubernetes](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/)).
Отсюда типовые пути: конфигурации лежат в `/etc/cni/net.d/` (conflist-файлы), бинарники — в `/opt/cni/bin/`.

Требования Kubernetes к плагину:
- плагин должен быть совместим с **v0.4.0 или новее** спецификации CNI; рекомендуется v1.0.0+;
- обязателен **loopback**-плагин (интерфейс `lo` для каждого sandbox);
- поддержка **hostPort** (обычно через `portmap`) и опционально **bandwidth** (traffic shaping) — оба официальные плагины из [containernetworking/plugins](https://github.com/containernetworking/plugins);
- в кластере можно установить **только одну** pod-сеть.

Сетевая модель Kubernetes — четыре правила ([Cluster Networking](https://kubernetes.io/docs/concepts/cluster-administration/networking/)):
1. pod'ы общаются со всеми pod'ами **без NAT**;
2. агенты (kubelet и др.) на ноде общаются со всеми pod'ами этой и других нод;
3. каждый pod имеет **свой уникальный IP** (в podCIDR);
4. агенты могут использовать сеть хоста.

Эту модель «реализует контейнерный рантайм на каждой ноде; самые распространённые рантаймы используют CNI-плагины,
причём одни дают лишь базовые функции добавления/удаления интерфейсов, а другие — более сложные решения: интеграцию
с оркестрацией, несколько CNI, продвинутый IPAM» ([Cluster Networking](https://kubernetes.io/docs/concepts/cluster-administration/networking/)).

### 1.4. CNI-плагин ≠ «сетевое решение» (networking solution)

Это ключевое различие для понимания экосистемы:

- **CNI-плагин** — реализация спецификации: бинарник(и), который вызывается рантаймом для одного конкретного
  подключения (ADD/DEL/CHECK/GC). Собственно «сеть подов» на ноде. Пример: `calico`, `cilium-cni`, `flannel`,
  `bridge`, `ptp`, `host-local` (IPAM).
- **Сетевое решение** — плагин(ы) **плюс control plane** для поддержания сети кластера в целом: распределение
  podCIDR и IP (IPAM), маршрутизация/оверлей между нодами, проброс Service (kube-proxy или замена),
  NetworkPolicy, BGP-пиринг, шифрование, наблюдаемость. Примеры: Calico (Felix + BIRD + calico-node + kube-controllers),
  Cilium (cilium-agent + cilium-operator + eBPF programs), Flannel (flanneld + kube subnet manager), kube-router.

То есть **CNI — это «интерфейс», а не «продукт»**. Одно и то же решение может быть собрано из разных
CNI-плагинов: например Canal = flannel (транспорт) + Calico (политики), а Cilium умеет работать в режиме
CNI chaining поверх другого плагина ([Cilium chaining](https://docs.cilium.io/en/stable/installation/cni-chaining/)).

---

## 2. Популярные CNI-решения и где они применяются

Ниже — обзор каждого решения. Популярность собрана из GitHub API (звёзды, архивность, дата последнего
push, 12.09.2026), документов CNCF и официальных доков.

### 2.1. Calico (Tigera/Project Calico)

- **Что это:** L3-решение для маршрутизации трафика между pod'ами. Работает в **overlay** (VXLAN, IP-in-IP) или в
  **BGP-режиме без оверлея** («direct infrastructure peering without the overlay»). Данные по умолчанию программирует
  через **iptables** (dataplane `felix`), есть **eBPF dataplane** (замена kube-proxy) ([About Calico](https://docs.tigera.io/calico/latest/about/)).
- **Фичи:** NetworkPolicy (в т.ч. расширенная — tiers, DNS-политики, глобальные политики), шифрование **WireGuard**,
  поддержка Windows, Cluster Mesh, VPP dataplane ([About Calico](https://docs.tigera.io/calico/latest/about/)).
- **Где применяется:** фактически «стандарт де-факто» для bare-metal и частных облаков, дефолт в MicroK8s,
  LKE, включается одной командой в k0s, RKE2 (в составе Canal). Tigera заявляет «100M+ контейнеров на 8M+ нод
  в 166 странах» ([About Calico](https://docs.tigera.io/calico/latest/about/)).
- **GitHub:** [projectcalico/calico](https://github.com/projectcalico/calico) — ~7,35k ⭐, активен (push 12.09.2026).
- Статус: Calico **не является проектом CNCF**; развивает компания Tigera.

### 2.2. Cilium (Isovalent/Cisco)

- **Что это:** eBPF-решение: сетевая логика выполняется **в ядре Linux** через eBPF-программы. Режимы: overlay
  (VXLAN, Geneve) или native routing. Полностью заменяет **kube-proxy** (socket-level LB без per-packet NAT),
  даёт **L7-политики** (HTTP, gRPC, DNS/FQDN), service mesh, Cluster Mesh, шифрование **IPsec или WireGuard**
  ([Introduction to Cilium](https://docs.cilium.io/en/stable/overview/intro/)).
- **Наблюдаемость:** Hubble — сервис-граф, flow-визуализация, метрики (включён по умолчанию в DOKS).
- **Где применяется:** стандарт для managed-провайдеров и eBPF-энтузиастов: **GKE Dataplane V2**, **AKS Azure CNI
  Powered by Cilium**, **DOKS**, **Civo**; активно используется AWS (в EKS как альтернатива VPC CNI).
  По отчёту CNCF, Cilium «adopted by all the major public clouds» и входит в [USERS.md](https://github.com/cilium/cilium/blob/main/USERS.md)
  (Adobe, Capital One, Google, Alibaba, DigitalOcean и др.) ([Cilium Project Journey Report](https://www.cncf.io/reports/cilium-project-journey-report/)).
- **CNCF:** graduated **11 октября 2023** (в CNCF с 13 октября 2021); 3 195+ контрибьюторов, 70 531+ коммитов
  ([Cilium Project Journey Report](https://www.cncf.io/reports/cilium-project-journey-report/)).
- **GitHub:** [cilium/cilium](https://github.com/cilium/cilium) — ~25,1k ⭐, самый активный проект в нише (push 12.09.2026).
- **Требования:** ядро Linux ≥ 4.9.17 (рекомендуется ≥ 5.8 для полной замены kube-proxy); **нет поддержки Windows**
  ([RKE2 Network Options](https://docs.rke2.io/networking/basic_network_options)).

### 2.3. Flannel

- **Что это:** «простой способ настроить layer 3 сетевую фабрику для Kubernetes» ([README](https://github.com/flannel-io/flannel/blob/master/README.md)).
  Бэкенды: **VXLAN** (по умолчанию), **host-gw** (прямые маршруты без инкапсуляции, требует L2 между нодами),
  **wireguard** (шифрование). Хранит состояние в kube-субнет-менеджере (или etcd). Не контролирует, как контейнер
  подключён к хосту, — только транспорт между нодами.
- **NetworkPolicy: не умеет нативно.** Варианты: встроенный [kube-network-policies](https://github.com/kubernetes-sigs/kube-network-policies)
  (в новом Helm-чарте), или связка с Calico (это и есть Canal), или chaining с Cilium
  ([README](https://github.com/flannel-io/flannel/blob/master/README.md)). Требует модуль `br_netfilter`.
- **Где применяется:** дефолт в **k3s** и **Talos**, исторически основной в kubeadm-туториалах.
- **GitHub:** [flannel-io/flannel](https://github.com/flannel-io/flannel) — ~9,5k ⭐, активен.
- Статус в CNCF: проект CNCF с 2017 года.

### 2.4. Canal

- **Что это:** не отдельный проект, а **связка**: Flannel для транспорта между нодами + Calico для политик
  и трафика внутри ноды. «Canal uses Flannel for inter-node traffic and Calico for intra-node traffic and
  network policies. By default, it will use vxlan encapsulation» ([RKE2 Network Options](https://docs.rke2.io/networking/basic_network_options)).
  Инструкция по установке — [раздел Calico docs «install for flannel»](https://docs.tigera.io/calico/latest/getting-started/kubernetes/flannel/install-for-flannel).
- **Где применяется:** **дефолт RKE2** (чарт `rke2-canal`). Позволяет получить NetworkPolicy ценой минимальной
  сложности поверх простого транспорта.

### 2.5. Weave Net — архивирован

- Weave Net долгое время был популярным решением (оверлей на базе собственного протокола, поддержка шифрования
  WireGuard, мультикаст). Однако проект **архивирован 20 июня 2024 года** (read-only): «This repository was archived
  by the owner on Jun 20, 2024» ([github.com/weaveworks/weave](https://github.com/weaveworks/weave)). Компания
  Weaveworks прекратила деятельность в начале 2024. **Использовать в новых кластерах не стоит**; миграция —
  на Calico/Cilium.

### 2.6. Antrea (VMware/Broadcom)

- **Что это:** Kubernetes-native решение на базе **Open vSwitch (OVS)**. Работает на L3/L4, использует OVS
  как dataplane, что даёт эффективный NetworkPolicy, возможность hardware offloading и **поддержку Windows**
  (та же реализация dataplane на Windows). Шифрование — **IPsec или WireGuard**, есть multi-cluster, Antrea-native
  политики (в т.ч. для VM через проект Nephe), инструменты диагностики и observability (Theia)
  ([Antrea README](https://github.com/antrea-io/antrea/blob/main/README.md)).
- **CNCF:** sandbox (принят **28 апреля 2021** ([CNCF](https://www.cncf.io/projects/antrea/))). Требует OVS-модуль ядра.
- **GitHub:** [antrea-io/antrea](https://github.com/antrea-io/antrea) — ~1,8k ⭐.
- **Где применяется:** ниша — кластеры, где нужен OVS / Windows-ноды / hardware offload; официально поддерживается
  Kubernetes (страница [Antrea NetworkPolicy](https://kubernetes.io/docs/tasks/administer-cluster/network-policy-provider/antrea-network-policy/)).
  Для homelab — избыточен.

### 2.7. Kube-router

- **Что это:** «turnkey-решение» в одном DaemonSet: **pod networking через BGP** (GoBGP, без оверлея), **service proxy
  на IPVS/LVS** (замена kube-proxy), **NetworkPolicy через iptables+ipset**, встроенный **LoadBalancer IP allocator**
  для bare-metal, продвинутый BGP (анонс ClusterIP/externalIP наружу, MD5-auth) ([kube-router README](https://github.com/cloudnativelabs/kube-router/blob/master/README.md)).
- **Ключевое:** использует **стандартный Linux-стек** (iptables, ipvsadm, ipset, iproute) и официальный `bridge`-плагин
  CNI — никаких оверлеев и отдельного datastore. Малый размер кода, высокая производительность.
- **Это дефолтный CNI в k0s** (см. раздел 4.1). Также k3s использует его **netpol-контроллер** (только policy,
  без остальной функциональности) ([k3s Networking Services](https://docs.k3s.io/networking/networking-services)).
- **GitHub:** [cloudnativelabs/kube-router](https://github.com/cloudnativelabs/kube-router) — ~2,5k ⭐.
  Проект малоактивен (последний push 07.09.2026, но коммитов мало; развитие идёт в основном через k0s/k3s).

### 2.8. Multus

- **Что это:** **meta-CNI-плагин**: позволяет поду иметь **несколько сетевых интерфейсов** (multi-homed pod).
  Вызывает другие CNI-плагины для дополнительных интерфейсов (`eth0` — основная pod-сеть, `net0`, `net1` — доп. сети).
  Конфигурация — через CRD `NetworkAttachmentDefinition`, стандарт Network Plumbing Working Group
  ([Multus README](https://github.com/k8snetworkplumbingwg/multus-cni/blob/master/README.md)).
- **Режимы:** «thin» (старый) и «thick» (client/server, метрики; рекомендуемый).
- **Где применяется:** SR-IOV, DPDK, GPU-фабрики (RDMA/NCCL), многосетевые поды. Входит в RKE2 как вторичный плагин
  и в MicroK8s как аддон, поддержан в GKE для multi-network. Для обычного homelab **не нужен**.
- **GitHub:** [k8snetworkplumbingwg/multus-cni](https://github.com/k8snetworkplumbingwg/multus-cni) — ~2,9k ⭐.

### 2.9. OVN-Kubernetes

- **Что это:** решение на базе **OVN (Open Virtual Network) + Open vSwitch**: конфигурация превращается в OpenFlow-правила,
  работает распределённая виртуальная маршрутизация, логические коммутаторы, DHCP, DNS, ACL ([OpenShift docs](https://docs.openshift.com/container-platform/4.17/networking/ovn_kubernetes_network_provider/about-ovn-kubernetes.html)).
- **Фичи:** NetworkPolicy (с логами), egress IP, **multicast**, **IPsec**, IPv6/dual-stack, hardware offloading.
- **Где применяется:** **дефолтный сетевой провайдер OpenShift** и SNO ([OpenShift docs](https://docs.openshift.com/container-platform/4.17/networking/ovn_kubernetes_network_provider/about-ovn-kubernetes.html)).
- **GitHub:** [ovn-kubernetes/ovn-kubernetes](https://github.com/ovn-kubernetes/ovn-kubernetes) — ~1,1k ⭐, активен.
- Для homelab без OpenShift — интересен только как учебный пример.

### 2.10. Облачные CNI

Облачные провайдеры часто используют **собственные CNI**, завязанные на сеть облака (без оверлея, pod IP = реальный
IP в VPC/VCN). Подробнее и с источниками — раздел 3.

| CNI | Провайдер | Суть |
|---|---|---|
| **Amazon VPC CNI** | AWS | Pod получает IP прямо из VPC (ENI/secondary IP); маршрутизация через таблицу маршрутов VPC |
| **Azure CNI** | Azure | Overlay или flat-модель с IP из VNet; опция «Powered by Cilium» |
| **GKE Dataplane V2** | Google | Cilium + eBPF, VPC-native; legacy dataplane — Calico |
| **OCI VCN-Native / Flannel** | Oracle OKE | Собственный VCN-Native CNI или классический Flannel |
| **Cilium** | DigitalOcean DOKS, Civo | eBPF, Hubble |
| **Calico** | Akamai LKE | BGP без оверлея |

### 2.11. Популярность: цифры

| Проект | GitHub ⭐ | Активность | CNCF | Роль на рынке |
|---|---|---|---|---|
| Cilium | ~25,1k | очень высокая (push 12.09.2026) | graduated (10.2023) | стандарт для eBPF и managed-облаков |
| Flannel | ~9,5k | высокая | проект CNCF (с 2017) | простейший дефолт (k3s, Talos) |
| Calico | ~7,35k | высокая | не в CNCF (Tigera) | «дефолт» bare-metal / политик |
| Weave Net | ~6,6k | **архив (06.2024)** | archived | использовать нельзя |
| Multus | ~2,9k | высокая | sandbox (NPWG) | многосетевые поды |
| Kube-router | ~2,5k | низкая | — | дефолт k0s; netpol k3s |
| Antrea | ~1,8k | высокая | sandbox (04.2021) | OVS/Windows/offload |
| OVN-Kubernetes | ~1,1k | высокая | — | дефолт OpenShift |

Цифры звёзд — GitHub API на 12.09.2026. Сводных «официальных» процентов рынка CNI нет: CNCF Annual Survey
не разбивает респондентов по CNI (см. [CNCF Annual Survey 2024](https://www.cncf.io/reports/cncf-annual-survey-2024/),
750 респондентов, опубликован 01.04.2025). Наиболее цитируемый (но **вторичный**) источник — отчёты
Red Hat/StackRox «State of Kubernetes and Container Security» ([stackrox.io/state-of-kubernetes-security](https://www.stackrox.io/state-of-kubernetes-security/)):
по ним Calico стабильно лидировал (~половина респондентов), а Cilium был самым быстрорастущим CNI. Точные проценты
из отчётов 2023–2024 гг. при переносе сюда могут устареть — проверяйте по первоисточнику.

---

## 3. Managed Kubernetes: какой CNI по умолчанию

| Провайдер | CNI по умолчанию | Источник (официальные доки) |
|---|---|---|
| **Amazon EKS** | **Amazon VPC CNI** — pod IP выдаётся из VPC (без оверлея); «Pod networking is provided by the Amazon VPC Container Network Interface (CNI) plugin» | [EKS networking](https://docs.aws.amazon.com/eks/latest/userguide/eks-networking.html) |
| **Azure AKS** | **Azure CNI** (overlay или flat); опция **Azure CNI Powered by Cilium** (Service routing через Cilium, без kube-proxy) | [AKS concepts-network](https://learn.microsoft.com/en-us/azure/aks/concepts-network) |
| **Google GKE** | **GKE Dataplane V2** — «enabled by default for all new Autopilot clusters»; реализован на **Cilium/eBPF**, legacy dataplane — **Calico** (iptables); VPC-native кластеры | [GKE Dataplane V2](https://cloud.google.com/kubernetes-engine/docs/concepts/dataplane-v2) |
| **Oracle OKE** | **Flannel CNI** (overlay) **или OCI VCN-Native Pod Networking CNI** (pod IP из VCN-сабнетов) | [OKE network config](https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengnetworkconfig.htm) |
| **DigitalOcean DOKS** | **Cilium** (Hubble включён по умолчанию; `hubble-relay`/`hubble-ui` в kube-system; Cilium обновляется с каждым релизом DOKS) | [DOKS: use Cilium Hubble](https://docs.digitalocean.com/products/kubernetes/how-to/use-cilium-hubble/), [changelog](https://docs.digitalocean.com/products/kubernetes/details/changelog/) |
| **Akamai LKE** (бывш. Linode) | **Calico** (BGP, порт 179; Calico Typha, порт 5473; pod-сеть 10.2.0.0/16; IPv6 не поддержан) | [LKE network and firewall details](https://techdocs.akamai.com/cloud-computing/docs/lke-network-firewall-details.md) |
| **Hetzner** | По общедоступной информации — **Cilium**; на момент исследования docs.hetzner.com был недоступен (HTTP 000/timeout), проверить по первоисточнику не удалось — **требует проверки** | [docs.hetzner.com/kubernetes](https://docs.hetzner.com/kubernetes/) |
| **Civo** | **Cilium** (дефолт); в Advanced options можно выбрать CNI; **Flannel и Talos помечены как deprecating** | [Civo: create a cluster](https://www.civo.com/docs/kubernetes/create-a-cluster) |

Наблюдение: **eBPF/Cilium стал де-факто стандартом новых managed-предложений** (GKE, AKS, DOKS, Civo),
тогда как «классические» bare-metal-провайдеры и самоуправляемые кластеры держатся за Calico/Flannel.

---

## 4. Дефолты дистрибутивов

### 4.1. k0s — дефолт: **Kube-router**, опция: **Calico**

- k0s «supports any standard CNI network provider» и в комплекте идёт с двумя встроенными: **Kube-router** и **Calico**.
  **По умолчанию используется Kube-router** ([k0s Networking](https://docs.k0sproject.io/stable/networking/)).
- Kube-router в k0s: стандартный Linux-стек, **без оверлеев**, BGP как основной механизм; «uses a bit less
  resources (~15%)»; **не поддерживает Windows** ([k0s Networking](https://docs.k0sproject.io/stable/networking/)).
- Calico в k0s: L3-решение, **VXLAN по умолчанию** (для IPv6 и dual-stack нужен режим `bird` = IP-in-IP),
  поддержка Windows, чуть больше ресурсов ([k0s Networking](https://docs.k0sproject.io/stable/networking/),
  [k0s dual-stack](https://docs.k0sproject.io/stable/dual-stack/)).
- Дефолтные CIDR: pod `10.244.0.0/16`, service `10.96.0.0/12` ([k0s dual-stack](https://docs.k0sproject.io/stable/dual-stack/)).
- Кастомный CNI: `spec.network.provider: custom` — тогда k0s не управляет сетью и CNI ставится Helm'ом/манифестами
  ([k0s Networking](https://docs.k0sproject.io/stable/networking/)).
- **«Once you initialize the cluster with a network provider the only way to change providers is through a
  full cluster redeployment»** — смена CNI в k0s = пересоздание кластера ([k0s Networking](https://docs.k0sproject.io/stable/networking/)).
- iptables: k0s автоопределяет режим `legacy`/`nftables` и **предпочитает nftables**; важно, чтобы firewalld
  использовал тот же бэкенд ([k0s Networking](https://docs.k0sproject.io/stable/networking/)).

### 4.2. k3s — дефолт: **Flannel**

- k3s по умолчанию ставит **Flannel** (VXLAN); бэкенды: `vxlan` (дефолт), `host-gw`, `wireguard-native`,
  `ipsec` (deprecated, удалят), `none` ([k3s Basic Network Options](https://docs.k3s.io/networking/basic-network-options)).
- Свой CNI: `--flannel-backend=none` + рекомендуется `--disable-network-policy`; в доке описаны шаги для
  **Canal** и **Calico** (нужно включить `allow_ip_forwarding` в `container_settings`) и для **Cilium**
  (при `k3s-uninstall.sh` требуется вручную удалить `cilium_host/cilium_net/cilium_vxlan` и iptables-правила)
  ([k3s Basic Network Options](https://docs.k3s.io/networking/basic-network-options)).
- **NetworkPolicy** в k3s из коробки обеспечивает встроенный контроллер на базе **netpol-библиотеки kube-router**
  (никакой другой функциональности kube-router там нет); отключается флагом `--disable-network-policy`
  ([k3s Networking Services](https://docs.k3s.io/networking/networking-services)).
- Dual-stack задаётся **только при создании кластера**, включить потом нельзя
  ([k3s Basic Network Options](https://docs.k3s.io/networking/basic-network-options)).

### 4.3. RKE2 — дефолт: **Canal**

- RKE2 бандлит **четыре CNI: Canal (по умолчанию), Cilium, Calico, Flannel**; плюс **Multus** как вторичный.
  Только Calico и Flannel поддерживают Windows. Выбор — ключ `cni` в `/etc/rancher/rke2/config.yaml`
  ([RKE2 Network Options](https://docs.rke2.io/networking/basic_network_options)).
- **RKE2 не поддерживает смену основного CNI на работающем кластере** — «Switching later is untested and may
  leave stale interfaces or routes behind; rebuild the cluster» ([RKE2 Network Options](https://docs.rke2.io/networking/basic_network_options)).
- Из нюансов: Flannel сам по себе «does not support network policies», поэтому не рекомендуется для hardened
  ([RKE2 Network Options](https://docs.rke2.io/networking/basic_network_options)); **kube-proxy в режиме IPVS
  объявлен deprecated начиная с Kubernetes v1.35** (удаление в будущем релизе)
  ([RKE2 Networking Services](https://docs.rke2.io/networking/networking_services),
  [Kubernetes 1.35 release notes](https://kubernetes.io/blog/2025/12/17/kubernetes-v1-35-release/)).

### 4.4. MicroK8s — дефолт: **Calico**

- Начиная с версии **1.19** MicroK8s использует **Calico CNI по умолчанию** с бэкендом VXLAN; конфиг —
  `/var/snap/microk8s/current/args/cni-network/cni.yaml` (daemonset `calico-node` + deployment
  `calico-kube-controllers`); дефолт pod CIDR `10.1.0.0/16`, service CIDR `10.152.183.0/24`
  ([MicroK8s CNI Configuration](https://microk8s.io/docs/change-cidr)).
- Альтернативы в аддонах: **cilium** (eBPF + NetworkPolicy), **kube-ovn**, **multus**, **metallb**
  ([MicroK8s addons](https://microk8s.io/docs/addons)).

### 4.5. Talos — дефолт: **Flannel**

- Talos по умолчанию ставит **Flannel**; смену CNI можно сделать через machine config
  (`machine.network`/CNI section в Talos docs). Официальная страница: [Talos Kubernetes Guides → Network → CNI](https://www.talos.dev/latest/kubernetes-guides/network/cni/).
  (Страница была доступна только частично на момент исследования — базовый факт «дефолт Flannel» широко
  известен и подтверждается конфигом `cniConfig` в Talos docs.)

### 4.6. kubeadm — **без CNI по умолчанию**

- kubeadm **не ставит сеть**: после `kubeadm init` нужно вручную «deploy a Pod network»; «Kubeadm should be
  CNI agnostic», «You can install only one Pod network per cluster»; под-сеть задаётся флагом `--pod-network-cidr`
  ([kubeadm: create cluster](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)).
  Это самый «честный» способ понять, как устроен CNI — но и самый трудоёмкий в эксплуатации.

### 4.7. OpenShift — дефолт: **OVN-Kubernetes**

- «The OVN-Kubernetes network plugin is the default network provider for OpenShift», overlay на базе OVN/OVS
  ([OpenShift docs](https://docs.openshift.com/container-platform/4.17/networking/ovn_kubernetes_network_provider/about-ovn-kubernetes.html)).

---

## 5. Сравнительная матрица возможностей

Легенда: ✅ да / ⚠️ частично, с оговоркой / ❌ нет / н/д — нет данных или не применимо.

| Критерий | Calico | Cilium | Flannel | Kube-router | Canal | Antrea | OVN-Kubernetes |
|---|---|---|---|---|---|---|---|
| **Overlay** | ✅ VXLAN / IP-in-IP | ✅ VXLAN/Geneve | ✅ VXLAN | ❌ нет (BGP) | ✅ VXLAN (flannel) | ✅/⚠️ overlay или no-overlay | ✅ overlay |
| **Native routing / без оверлея** | ✅ BGP, direct | ✅ native routing | ⚠️ host-gw (L2) | ✅ BGP | ⚠️ как flannel | ✅ | ⚠️ да, с OVS |
| **Dataplane** | iptables / nftables / **eBPF** | **eBPF** | iptables/route | iptables+ipset+**IPVS** | iptables | OVS | OVS/OpenFlow |
| **NetworkPolicy** | ✅ (расширенные) | ✅ (вкл. L7) | ❌ нативно | ✅ | ✅ (Calico) | ✅ (Antrea-native) | ✅ |
| **Шифрование** | ✅ WireGuard | ✅ IPsec/WireGuard | ✅ WireGuard-бэкенд | ❌ | ✅ WireGuard (flannel backend) | ✅ IPsec/WireGuard | ✅ IPsec |
| **BGP** | ✅ | ✅ | ❌ | ✅ (GoBGP) | ⚠️ через Calico | ⚠️ | ⚠️ OVN |
| **Service mesh / L7** | ⚠️ (Enterprise/Cloud) | ✅ (L7 policies, mesh, Gateway API) | ❌ | ❌ | ❌ | ❌ | ❌ |
| **kube-proxy replacement** | ✅ (eBPF dataplane) | ✅ | ❌ | ✅ (IPVS) | ❌ | ✅ | ⚠️ |
| **IPv6 / dual-stack** | ✅ (VXLAN не для IPv6 → bird) | ✅ | ✅ | ✅ (в k0s) | ✅ | ✅ | ✅ |
| **Multicast** | ❌ | ⚠️ | ❌ | ❌ | ❌ | ❌ | ✅ |
| **Windows-ноды** | ✅ | ❌ | ✅ | ❌ | ❌ (не поддержан в RKE2) | ✅ | ⚠️ |
| **Ресурсы / overhead** | средний | выше среднего (eBPF-мапы, агенты) | **низкий** | **низкий** (~15% меньше kube-router в k0s) | низкий | средний (OVS) | высокий (OVS/центральные БД) |
| **Сложность эксплуатации** | средняя | **высокая** (много фич, eBPF, оператор) | низкая | низкая | низкая | средняя | высокая |
| **Где дефолт** | MicroK8s, LKE, k0s(опц.) | GKE, AKS(опц.), DOKS, Civo | k3s, Talos, OKE | **k0s** | RKE2 | — | OpenShift |

Помесячные оговорки:
- **Cilium в GKE/DPv2**: eBPF-мапы ограничены 260 000 endpoint'ов, у GKE свои ограничения на кастомные eBPF-программы
  ([GKE Dataplane V2](https://cloud.google.com/kubernetes-engine/docs/concepts/dataplane-v2)).
- **Flannel не умеет NetworkPolicy** — отсюда рекомендация RKE2 не использовать его для hardened ([RKE2](https://docs.rke2.io/networking/basic_network_options)).
- **kube-router**: «no overlays, just plain good old networking»; сервис-прокси на IPVS, LoadBalancer-аллокатор встроен
  ([kube-router README](https://github.com/cloudnativelabs/kube-router/blob/master/README.md)).

---

## 6. Практические рекомендации для homelab на k0s

### 6.1. Окружение

- k0s (single-node, планируется вторая нода), MetalLB в режиме **L2** (пул `<metallb-ip>/32`), Tailscale для
  удалённого доступа, домен `example.com`, миграция с Docker Compose (см.
  [remote-access-metallb-solutions.md](./remote-access-metallb-solutions.md)).

### 6.2. Взаимодействие с MetalLB L2 и Tailscale — важный вывод

- **Выбор CNI ортогонален MetalLB L2.** MetalLB в L2-режиме работает на уровне ARP и не зависит от того,
  как устроена pod-сеть: LoadBalancer-IP превращается в kube-proxy/iptables-правила на ноде
  ([remote-access-metallb-solutions.md](./remote-access-metallb-solutions.md)). Требование одно: **podCIDR и
  serviceCIDR не должны пересекаться** ни с LAN (`<node1-lan-cidr>`), ни с пулом MetalLB (`<metallb-ip>/32`).
  Дефолтные k0s-CIDR (`10.244.0.0/16` и `10.96.0.0/12`) этому удовлетворяют.
- **Tailscale тоже не пересекается с CNI**: pod-сеть (оверлей или BGP) живёт внутри кластера, а Tailscale
  работает на L3-туннеле к хосту. Проблема «MetalLB L2 не маршрутизируется через Tailscale» (см. упомянутый
  док) решается не сменой CNI, а другой схемой доступа (Cloudflare Tunnel / Tailscale Serve / маршрутизация
  подсетей), и к выбору CNI отношения не имеет.
- **Единственный реальный конфликт «CNI × окружение»:** Calico в режиме BGP (`bird`) начинает пирить/анонсить
  маршруты — на L2-сегменте с одним-двумя узлами это избыточно и может потребовать настройки; для homelab
  проще VXLAN-режим Calico или BGP kube-router внутри кластера.

### 6.3. Что выбрать в k0s

В k0s выбор фактически между **Kube-router (дефолт)** и **Calico** (обе встроены), либо кастомный CNI
(**Cilium** и др.) через `spec.network.provider: custom`.

| Вариант | Плюсы | Минусы |
|---|---|---|
| **Kube-router (дефолт)** | Ноль настройки; минимальные ресурсы (~15% меньше); BGP-роутинг без оверлея; IPVS-прокси; учебно ценен (стандартный Linux-стек) | Малоактивен upstream; нет L7; нет шифрования; нет Windows; NetworkPolicy проще чем у Calico |
| **Calico** | Встроен в k0s (одна строка в конфиге); NetworkPolicy (расширенные); WireGuard-шифрование; де-факто стандарт enterprise; поддержка Windows | Чуть больше ресурсов; VXLAN-оверлей (лишний слой на одном хосте); eBPF-dataplane в k0s не встроен |
| **Cilium (custom)** | Самая «резюме-ценная» технология (eBPF, Hubble, L7, замена kube-proxy); используется в GKE/AKS/DOKS | В k0s не встроен — ставится отдельно (`provider: custom`); **смена CNI = пересоздание кластера**; самые высокие требования к ядру и ресурсам |

### 6.4. Рекомендация

**Двухшаговый план:**

1. **Начать с дефолтного Kube-router в k0s** — ноль конфигурации, минимум ресурсов, работает сразу, и это
   правильный способ понять «голый» сетевой стек (BGP, IPVS, iptables) без оверлеев. Подходит для одного узла
   и будущей второй ноды в одной LAN (BGP-mesh между узлами строится автоматически).

2. **Как учебное упражнение — переключиться на Calico** (встроен в k0s, `spec.network.provider: calico`,
   режим `vxlan`). Это даст: полноценный NetworkPolicy (микрос сегментация — production-grade навык),
   **WireGuard-шифрование** межнодового трафика (пригодится, когда вторая нода окажется в другой сети
   `<node2-lan-cidr>`), и опыт, переносимый на «взрослые» кластеры (Calico — стандарт bare-metal).

3. **Cilium — опциональный «столб» на потом**, когда захочется eBPF/Hubble/L7: ставить его стоит только на
   **свежий кластер** (или сознательно пересоздать), потому что смена CNI в k0s требует пересоздания.

> Если цель — быстрое рабочее решение, а не обучение: оставайтесь на дефолтном Kube-router. Если цель —
> «прод-градусный» скилл, который котируется в индустрии: сделайте Calico (встроен) и поднимите Cilium
> отдельно в тестовом кластере, чтобы сравнить ощущения до принятия решения о продакшене.

### 6.5. Чек-лист перед выбором (dev-практика)

- PodCIDR/serviceCIDR не пересекаются с LAN и пулом MetalLB (дефолтные `10.244.0.0/16` / `10.96.0.0/12` — ок).
- Решение о CNI принимается **до** `k0s install` — потом только пересоздание.
- iptables-бэкенд (legacy/nftables) k0s и firewalld на хосте должны совпадать ([k0s Networking](https://docs.k0sproject.io/stable/networking/)).
- Для Calico-WireGuard убедиться, что UDP-порт 51820 открыт между нодами (для будущей второй ноды).
- Один CNI на кластер; Multus — только если появятся реальные многосетевые задачи (маловероятно в homelab).

---

## 7. Миграция и смена CNI: риски и практика

### 7.1. Главное правило: CNI выбирается при создании кластера

Все крупные дистрибутивы прямо предупреждают:

- **k0s:** «Once you initialize the cluster with a network provider the only way to change providers is through
  a full cluster redeployment» ([k0s Networking](https://docs.k0sproject.io/stable/networking/)).
- **RKE2:** «RKE2 does not support changing the primary CNI Plugin… Switching later is untested and may leave
  stale interfaces or routes behind; rebuild the cluster» ([RKE2](https://docs.rke2.io/networking/basic_network_options)).
- **k3s:** дефолтный Flannel можно отключить (`--flannel-backend=none`) и поставить свой CNI, но:
  - при установке Cilium и последующем `k3s-uninstall.sh` нужно вручную удалить интерфейсы
    `cilium_host`, `cilium_net`, `cilium_vxlan` и cilium-правила iptables — иначе можно потерять сетевую
    связность хоста ([k3s Basic Network Options](https://docs.k3s.io/networking/basic-network-options));
  - netpol-правила kube-router **не удаляются** сами при отключении контроллера — чистить вручную:
    `iptables-save | grep -v KUBE-ROUTER | iptables-restore` ([k3s Networking Services](https://docs.k3s.io/networking/networking-services)).

### 7.2. Если смена всё же нужна (рецепт)

1. **Зафиксировать и выгрузить манифесты** всех приложений (при GitOps это просто — push уже в git).
2. **Снести кластер** (`k0s reset` / `k3s-uninstall.sh` / `rke2-uninstall.sh`), **удалить остатки CNI с хоста**:
   интерфейсы (`cni0`, `cilium_host`, `cilium_net`, `cilium_vxlan`, `flannel.1`), файлы `/etc/cni/net.d/*`,
   бинарники `/opt/cni/bin/*` (если ставились вручную), stale-маршруты в таблице маршрутизации.
3. **Почистить iptables/nftables** от старых цепочек (KUBE-*, KUBE-ROUTER, CILIUM-, CALICO-, FLANNEL-):
   `iptables-save | grep -v KUBE-ROUTER | iptables-restore` — по аналогии с [k3s](https://docs.k3s.io/networking/networking-services).
4. **Пересоздать кластер с новым `spec.network.provider`** и применить манифесты.

### 7.3. Риски

- **Перезагрузка нод** обычно безопасна для работающего CNI (состояние восстанавливается), но **файлы CNI-конфигурации
  и бинарники должны быть установлены стабильно** (в k0s/RKE2 они часть дистрибутива — ок; при кастомном CNI
  через Helm — Helm-чарт переживает reboot, но проверьте, что DaemonSet встаёт в Running).
- **Остаточные iptables-правила** — самый частый источник «магии» после смены CNI; чистите целиком, не по одному правилу.
- **Смена CNI не бывает rolling**: это не «обновить DaemonSet», а смена модели данных плоскости (BGP→overlay и т.п.)
  — планируйте downtime.
- **dual-stack**: если хотите IPv6/dual-stack — включайте **сразу при создании**, потом не включить
  ([k3s](https://docs.k3s.io/networking/basic-network-options), [k0s](https://docs.k0sproject.io/stable/dual-stack/)).
- **Calico + IPv6**: VXLAN-режим не умеет IPv6-туннелирование — нужен `bird` (IP-in-IP) ([k0s dual-stack](https://docs.k0sproject.io/stable/dual-stack/)).

---

## 8. Источники

**Спецификация и Kubernetes:**
- CNI Specification v1.1.0: https://github.com/containernetworking/cni/blob/main/SPEC.md
- CNI plugins (bridge, portmap, bandwidth и т.д.): https://github.com/containernetworking/plugins
- Kubernetes Network Plugins: https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/
- Kubernetes Cluster Networking: https://kubernetes.io/docs/concepts/cluster-administration/networking/
- kubeadm — create cluster (pod network add-on): https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
- Kubernetes NetworkPolicy providers (Antrea/Calico/Cilium/kube-router): https://kubernetes.io/docs/tasks/administer-cluster/network-policy-provider/
- Konnectivity: https://kubernetes.io/docs/tasks/extend-kubernetes/setup-konnectivity/
- Kubernetes v1.35 release notes (deprecation IPVS в kube-proxy): https://kubernetes.io/blog/2025/12/17/kubernetes-v1-35-release/

**Дистрибутивы:**
- k0s Networking (CNI): https://docs.k0sproject.io/stable/networking/
- k0s dual-stack: https://docs.k0sproject.io/stable/dual-stack/
- k3s Basic Network Options: https://docs.k3s.io/networking/basic-network-options
- k3s Networking Services (netpol kube-router, ServiceLB): https://docs.k3s.io/networking/networking-services
- RKE2 Network Options (Canal/Cilium/Calico/Flannel, Multus): https://docs.rke2.io/networking/basic_network_options
- RKE2 Networking Services: https://docs.rke2.io/networking/networking_services
- MicroK8s CNI Configuration: https://microk8s.io/docs/change-cidr
- MicroK8s addons: https://microk8s.io/docs/addons
- Talos — Network guides: https://www.talos.dev/latest/kubernetes-guides/network/cni/
- OpenShift — OVN-Kubernetes: https://docs.openshift.com/container-platform/4.17/networking/ovn_kubernetes_network_provider/about-ovn-kubernetes.html

**Проекты:**
- Cilium — Introduction: https://docs.cilium.io/en/stable/overview/intro/
- Calico — About: https://docs.tigera.io/calico/latest/about/
- Calico — Canal (flannel + calico): https://docs.tigera.io/calico/latest/getting-started/kubernetes/flannel/install-for-flannel
- Flannel README: https://github.com/flannel-io/flannel/blob/master/README.md
- kube-router README: https://github.com/cloudnativelabs/kube-router/blob/master/README.md
- Antrea README: https://github.com/antrea-io/antrea/blob/main/README.md
- Multus README: https://github.com/k8snetworkplumbingwg/multus-cni/blob/master/README.md
- OVN-Kubernetes README: https://github.com/ovn-kubernetes/ovn-kubernetes/blob/master/README.md
- Weave Net (архив): https://github.com/weaveworks/weave

**Облака:**
- EKS networking (Amazon VPC CNI): https://docs.aws.amazon.com/eks/latest/userguide/eks-networking.html
- AKS networking concepts (Azure CNI, Cilium): https://learn.microsoft.com/en-us/azure/aks/concepts-network
- GKE Dataplane V2: https://cloud.google.com/kubernetes-engine/docs/concepts/dataplane-v2
- OKE network configuration (Flannel / VCN-Native): https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengnetworkconfig.htm
- DOKS (Cilium Hubble): https://docs.digitalocean.com/products/kubernetes/how-to/use-cilium-hubble/ и https://docs.digitalocean.com/products/kubernetes/details/changelog/
- LKE network/firewall details (Calico): https://techdocs.akamai.com/cloud-computing/docs/lke-network-firewall-details.md
- Hetzner K8s (недоступен на момент исследования): https://docs.hetzner.com/kubernetes/
- Civo — create a cluster (CNI selection): https://www.civo.com/docs/kubernetes/create-a-cluster

**Отчёты и статистика:**
- CNCF Annual Survey 2024: https://www.cncf.io/reports/cncf-annual-survey-2024/
- Cilium Project Journey Report (CNCF): https://www.cncf.io/reports/cilium-project-journey-report/
- CNCF Antrea project page (sandbox): https://www.cncf.io/projects/antrea/
- Red Hat/StackRox State of Kubernetes Security (вторичный источник по долям CNI): https://www.stackrox.io/state-of-kubernetes-security/
- GitHub API (звёзды/активность, 12.09.2026): https://api.github.com/repos/{cilium/cilium|projectcalico/calico|flannel-io/flannel|cloudnativelabs/kube-router|antrea-io/antrea|k8snetworkplumbingwg/multus-cni|ovn-kubernetes/ovn-kubernetes|weaveworks/weave|containernetworking/cni}