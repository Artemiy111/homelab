# K3s vs k0s: детальное сравнение

Дата исследования: 2026-08-27.

## Обзор

| | **K3s** | **k0s** |
|---|---|---|
| Создатель | Rancher (SUSE) | Mirantis |
| Лицензия | Apache-2.0 | Apache-2.0 |
| CNCF статус | Sandbox (авг 2020) | Sandbox (янв 2025) |
| GitHub ⭐ | ~33.8k | ~6.5k |
| Контрибьюторы | ~5,689 | ~1,569 |
| Девиз | «Lightweight Kubernetes» | «Zero Friction Kubernetes» |
| Философия | **Batteries-included** — всё из коробки | **Minimal base** — минимальное ядро, остальное по выбору |

---

## 1. Архитектура

### K3s

- Один бинарник, содержащий **все** компоненты Kubernetes + containerd + flannel + Traefik + CoreDNS + metrics-server + local-path-provisioner + helm-controller + ServiceLB
- Server node = control-plane + kubelet + container runtime + CNI
- Agent node = kubelet + container runtime + CNI
- Серверные процессы работают **как контейнеры** (static pods)
- Агенты подключаются к серверам через **websocket-туннели** (обратные — агент инициирует исходящее соединение)
- Клиентский load-balancer на порту 6443, автоматически обновляет список серверов из Kubernetes service endpoint list
- **Containerd 2.x** (с февраля 2025) как CRI по умолчанию, можно переключить на Docker через `--docker` (кри-dockerd)
- Kernel-space: kube-proxy, iptables/nftables

### k0s

- Один самораспаковывающийся бинарник, статически скомпилированный
- **Контроллеры не запускают containerd/kubelet** — control-plane работает как «голые» процессы (naked process supervision), без контейнерного рантайма
- Worker-ноды: **containerd + runc** как CRI
- Связь контроллер-воркер: **Konnectivity service** (реверс-туннель через порт 8132), не websocket-туннели как в K3s
- k0s сам управляет жизненным циклом etcd (встроенное кластерное etcd)
- Поддержка **experimental Windows Server** (2019/2022) — k0s supervises `kubelet.exe` и `kube-proxy.exe`

**Ключевое отличие:** K3s запускает kubelet + containerd на **всех** узлах (включая server); k0s **отделяет** control-plane от worker'ов — на контроллерах нет kubelet/containerd, что делает control-plane более изолированным и предсказуемым.

---

## 2. Минимальные ресурсы

### K3s

| Роль | CPU | RAM |
|---|---|---|
| Server | 2 core | 2 GB |
| Agent | 1 core | 512 MB |

Рекомендации для sizing:
- 2 core / 4 GB → до 350 агентов
- 4 core / 8 GB → до 900 агентов
- 8 core / 16 GB → до 1800 агентов

### k0s

| Роль | CPU | RAM |
|---|---|---|
| Controller | 1 vCPU | 1 GB |
| Worker | 1 vCPU | 512 MB |
| Controller+Worker | 1 vCPU | 1 GB |

Измеренный расход памяти контроллера (k0s v1.22.4+k0s.2):
- Пустой контроллер: ~510 MB
- 20 воркеров / 2000 подов: ~1,000 MB
- 100 воркеров / 10,000 подов: ~2,300 MB
- 200 воркеров / 20,000 подов: ~3,300 MB

Рекомендации:
- 10 воркеров / 1,000 подов: 1-2 GB RAM / 1-2 vCPU
- 100 воркеров / 10,000 подов: 4-8 GB RAM / 2-4 vCPU
- 1000 воркеров / 100,000 подов: 16-32 GB RAM / 8-16 vCPU

### Вердикт

k0s **формально легче** на контроллере (1 GB vs 2 GB), но в реальности разница ~500 MB при пустом кластере. Для homelab-сценария оба укладываются.

---

## 3. Поддерживаемые ОС и архитектуры

### Архитектуры

| | K3s | k0s |
|---|---|---|
| x86_64 (amd64) | ✅ | ✅ |
| ARM64 (aarch64) | ✅ | ✅ |
| ARMv7 (armhf) | ✅ | ✅ |
| ARMv6 | ✅ | ❌ |
| s390x | ✅ | ❌ |
| RISC-V | ❌ | ✅ (без пребилдов, нет CI) |
| Windows | ❌ | ✅ (экспериментально, Server 2019/2022) |

### ОС (CI-тестирование)

**K3s** поддерживает «большинство современных Linux»: RHEL/CentOS/Fedora, Ubuntu/Debian, SUSE/openSUSE, Raspberry Pi OS. На RHEL 10 нужен `kernel-modules-extra`. На Fedora нужна настройка firewalld.

**k0s** CI-тестирован на 12 ОС:
- Amazon Linux 2023
- Alpine 3.21/3.23
- CentOS Stream 9/10
- Debian 11/12
- Fedora CoreOS (stable)
- Fedora 41 (Cloud)
- Flatcar Container Linux
- RHEL 7.9, 8.10, 9.7
- Rocky 8.10/9.5
- SLES 15 SP6
- Ubuntu 20.04/22.04/24.04

---

## 4. Из коробки vs. что ставить самому

### Что встроено и включено по умолчанию

| Компонент | K3s | k0s |
|---|---|---|
| **Container Runtime** | ✅ containerd 2.x | ✅ containerd 2.x |
| **CNI** | ✅ Flannel (VXLAN/host-gw/wireguard) | ✅ Kube-router (BGP, без overlay) |
| **Альтернативный CNI** | 🔧 `--flannel-backend=none` + Calico/Cilium/Canal | ✅ Calico встроен (выбор в конфиге) |
| **Custom CNI** | ✅ `--flannel-backend=none --disable-network-policy` | ✅ `provider: custom` |
| **CoreDNS** | ✅ | ✅ |
| **Metrics Server** | ✅ | ✅ |
| **Ingress Controller** | ✅ **Traefik v3** (порты 80/443) | ❌ **Нет** (Traefik/NGINX ставить самому) |
| **LoadBalancer** | ✅ **ServiceLB** (Klipper-lb) | ❌ **Нет** (MetalLB ставить самому) |
| **Storage Provisioner** | ✅ **local-path** (`ReadWriteOnce`) | ❌ **Нет** (Longhorn/OpenEBS ставить самому) |
| **Helm-интеграция** | ✅ **helm-controller** (HelmChart CRD) | ✅ **Chart CRD** (helm.k0sproject.io/v1beta1) |
| **Auto-deploy манифестов** | ✅ `/var/lib/rancher/k3s/server/manifests` | ✅ `/var/lib/k0s/manifests/` |
| **Network Policy Controller** | ✅ (kube-router netpol library) | ✅ (kube-router встроен) |
| **kube-proxy** | ✅ | ✅ (отключаемый, 4 режима) |
| **Konnectivity** | ❌ (websocket-туннели) | ✅ |
| **Node-local Load Balancing** | ❌ | ✅ EnvoyProxy или Traefik |
| **Control-plane Load Balancing** | ❌ (нужен внешний LB/HAProxy) | ✅ Keepalived (VRRP) |
| **Autopilot (автообновления)** | ❌ (system-upgrade-controller отдельно) | ✅ встроен |
| **Backup/Restore CLI** | ❌ (etcdctl руками) | ✅ `k0s backup` / `k0s restore` |
| **Собственный LB для control-plane** | ❌ | ✅ Keepalived |
| **Token management CLI** | 🔧 (команды есть, но менее формализованы) | ✅ `k0s token create/list/invalidate` |

### Что нужно ставить самому в K3s (если хочется)

| Компонент | Как добавить |
|---|---|
| LoadBalancer (MetalLB) | `kubectl apply` манифеста (ServiceLB конфликтует — отключить `--disable=servicelb`) |
| Ingress (NGINX вместо Traefik) | `--disable=traefik` + установка nginx-ingress chart |
| Distributed Storage (Longhorn) | `kubectl apply` Longhorn YAML |
| GitOps (Flux/Argo) | `kubectl apply` манифестов |
| Monitoring (Prometheus+Grafana) | `kubectl apply` kube-prometheus-stack |
| Cert-Manager | `kubectl apply` манифеста |
| Dashboard | `kubectl apply` |

### Что нужно ставить самому в k0s

| Компонент | Как добавить |
|---|---|
| Ingress (Traefik/NGINX) | Chart CRD или k0s.yaml helm config |
| LoadBalancer (MetalLB) | Chart CRD (пример в доках) |
| Distributed Storage (Longhorn/OpenEBS) | Chart CRD или манифесты |
| GitOps (Flux) | Chart CRD (пример в доках) |
| Monitoring (Prometheus+Grafana) | Chart CRD |
| Cert-Manager | Chart CRD |
| Dashboard | Манифесты |

**Вывод:** K3s «батарейки в комплекте» — из коробки рабочий стек для homelab (ingress + LB + storage + helm). k0s даёт **минимальное ядро** и больше гибкости в выборе компонентов, но больше ручной работы при настройке.

---

## 5. Хранилище данных (Datastore)

### K3s

| Тип | Описание |
|---|---|
| **SQLite** (по умолчанию) | Встроенный, через kine. Только для single-server. Самый простой вариант |
| **Embedded etcd** | Встроенный, запуск через `--cluster-init`. 3/5/7 серверов для кворума |
| **Внешний etcd** | Кластер etcd 3.5.21 |
| **MySQL** | 8.0, 8.4 |
| **MariaDB** | 10.11, 11.4 |
| **PostgreSQL** | 15.12, 16.7, 17.3 |

Особенности:
- **Автоматические snapshot'ы** etcd: по cron (по умолчанию каждые 12ч), хранение 5 штук
- **S3-бэкапы** snapshot'ов (AWS S3 или совместимые)
- **Миграция SQLite → etcd**: просто перезапуск с `--cluster-init` (авто-миграция)
- Настройка через CLI-флаги или env-переменные (K3S_DATASTORE_*)
- Для PostgreSQL с PgBouncer нужна доп. настройка prepared statements

### k0s

| Тип | Описание |
|---|---|
| **etcd** (по умолчанию) | k0s управляет полным жизненным циклом кластерного etcd |
| **kine** | SQLite, MySQL, PostgreSQL, dqlite через kine |
| **Внешний etcd** | `spec.storage.etcd.externalCluster` |

Особенности:
- k0s **не может уменьшить кластер etcd** — нужно вручную удалять ноду из etcd перед выключением
- Смена CNI-провайдера **требует полного пересоздания кластера**
- `k0s backup` / `k0s restore` — встроенные команды для бэкапа/восстановления

### Вердикт

K3s более гибок: SQLite для single-node, встроенное etcd для HA, внешние БД (MySQL/PostgreSQL) для enterprise. Автоматические snapshot'ы и S3-бэкапы — огромный плюс для продакшена. k0s по умолчанию сразу etcd (даже для single-node), что проще для понимания, но тяжелее для минимального single-node сценария.

---

## 6. Сеть (Networking)

### K3s — Flannel

| Backend | Описание |
|---|---|
| **VXLAN** (по умолчанию) | Инкапсуляция, работает на L3/L2 |
| **host-gw** | IP-маршрутизация, требует L2-связности |
| **wireguard-native** | Шифрование через WireGuard |
| **ipsec** | strongSwan IPSec (deprecated) |
| **none** | Отключение Flannel для стороннего CNI |

Дополнительно:
- IPv4/IPv6 dual-stack (настройка при создании кластера)
- Flannel options: `--flannel-ipv6-masq`, `--flannel-external-ip`, `--flannel-iface`
- Egress selector modes: `disabled`, `agent` (по умолчанию), `pod`, `cluster`
- Network Policy Controller использует kube-router netpol library (НЕ сам kube-router)
- Логирование сетевых policy через iptables NFLOG

### k0s — Kube-router

| Параметр | Описание |
|---|---|
| BGP-маршрутизация | Без overlay-сетей, напрямую через BGP |
| Resource usage | ~15% меньше, чем Calico |
| hairpin | Enabled/Allowed/Disabled |
| autoMTU | true (по умолчанию) |
| ipMasq | false (по умолчанию) |
| peerRouterIPs/ASNs | DEPRECATED |

**Альтернативы в k0s:**

| CNI | Описание |
|---|---|
| **Calico** | L3-маршрутизация, VXLAN (по умолчанию) или bird mode, поддержка WireGuard, **поддерживает Windows** |
| **custom** | Полностью кастомный CNI |

### kube-proxy

| Режим | K3s | k0s |
|---|---|---|
| iptables | ✅ (по умолчанию) | ✅ (по умолчанию) |
| ipvs | ✅ (через kubelet-arg) | ✅ |
| nftables | ✅ (через kubelet-arg) | ✅ |
| userspace | ❌ | ✅ |
| Отключение | ✅ `--disable-kube-proxy` | ✅ `spec.network.kubeProxy.disabled: true` |

### Node-local Load Balancing

| | K3s | k0s |
|---|---|---|
| Встроен | ❌ | ✅ |
| Типы | — | EnvoyProxy (по умолчанию) или Traefik |
| Использование | — | Балансировка доступа к API с воркеров |

### Control-plane Load Balancing

| | K3s | k0s |
|---|---|---|
| Встроен | ❌ | ✅ |
| Механизм | — | Keepalived (VRRP) |
| Настройки | — | virtualIPs, interface, virtualRouterID, unicast, lbAlgo (rr/wrr/lc/wlc/...), lbKind (DR/NAT/TUN) |

**Для K3s HA** нужен внешний LB (HAProxy, nginx, cloud LB) перед контроллерами. **Для k0s** есть встроенный Keepalived — VIP настраивается прямо в конфиге.

### Порты

| Протокол | K3s | k0s |
|---|---|---|
| API Server | 6443 | 6443 |
| etcd peer | 2379-2380 (HA) | 2380 |
| kubelet | 10250 | 10250 |
| Konnectivity | — | 8132 |
| k0s controller join API | — | 9443 |
| BGP (kube-router) | — | 179 |
| VXLAN (Flannel) | UDP 8472 | — |
| VXLAN (Calico) | — | UDP 4789 |
| WireGuard | UDP 51820/51821 | — |
| Embedded registry (Spegel) | TCP 5001/6443 | — |
| Keepalived VRRP | — | TCP 112 |

---

## 7. Конфигурация

### K3s

**Формат:** YAML-файл + CLI-флаги + env-переменные

**Пути:**
- Основной: `/etc/rancher/k3s/config.yaml`
- Drop-in: `/etc/rancher/k3s/config.yaml.d/*.yaml`
- Kubelet: `/var/lib/rancher/k3s/agent/etc/kubelet.conf.d/`
- Containerd: `/var/lib/rancher/k3s/agent/etc/containerd/config.toml`
- Data: `/var/lib/rancher/k3s`

**Приоритет:** CLI > env > config файл (alphabetical)

**Особенности:**
- Merge: последнее значение побеждает; `+` суффикс для append
- Kubelet args через `--kubelet-arg=key=value` или конфиг-файлы
- Containerd конфиг через шаблоны: `config-v3.toml.tmpl` (containerd 2.x) или `config.toml.tmpl` (1.7)
- Kubernetes component overrides: `--etcd-arg`, `--kube-apiserver-arg`, `--kube-scheduler-arg`, `--kube-controller-manager-arg`, `--kube-cloud-controller-manager-arg`, `--kube-proxy-arg`

### k0s

**Формат:** YAML-файл (`k0s.k0sproject.io/v1beta1`, kind: `ClusterConfig`)

**Пути:**
- Основной: `/etc/k0s/k0s.yaml`
- Data: `/var/lib/k0s/`
- PKI: `/var/lib/k0s/pki/`
- Manifests: `/var/lib/k0s/manifests/`
- Images (airgap): `/var/lib/k0s/images/`
- Bundled binaries: `/var/lib/k0s/bin/`
- Kubelet: `/var/lib/k0s/kubelet/` (настраивается через `--kubelet-root-dir`)

**Структура конфига:**
```yaml
apiVersion: k0s.k0sproject.io/v1beta1
kind: ClusterConfig
spec:
  api: ...          # API server, CA, SANs
  storage: ...      # etcd или kine
  network: ...      # CNI, pod/service CIDR, kube-proxy, NLLB, CP-LB
  controllerManager: ...
  scheduler: ...
  workerProfiles: ...
  featureGates: ...
  images: ...
  extensions: {helm: ...}
  konnectivity: ...
  telemetry: ...
```

**Особенности:**
- Partial config: незаполненные поля = дефолты
- Feature gates с привязкой к компонентам (apiserver, controller-manager, kubelet, scheduler, kube-proxy)
- Component Patches (экспериментально): JSON/MergePatch/StrategicMergePatch для coreDNS, kube-proxy, kube-router, Calico, metrics-server
- Worker profiles: переопределение kubelet config по ролям узлов
- `--disable-components` для полного отключения компонентов: applier-manager, autopilot, coredns, csr-approver, helm, konnectivity-server, kube-controller-manager, kube-proxy, kube-scheduler, metrics-server, network-provider, и др.

---

## 8. Обновления

### K3s

**Ручное обновление:**
```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=vX.Y.Z+k3s1 sh -s -
```

**Автоматическое:** через **system-upgrade-controller** (отдельно ставится):
- Plan CRD: `concurrency`, `cordon`, `prepare`, `channel`, `version`, `window`
- Запрет даунгрейда (отказ при попытке)
- Планирование по временным окнам (дни, время, таймзона)
- Серверы обновляются **по одному**, воркеры — по batches

**Релиз-каналы:** `stable` (по умолчанию), `latest`, `v1.33`, `v1.34`, `v1.35`, `v1.36`

### k0s

**Ручное обновление:**
```bash
sudo k0s stop
curl --proto '=https' --tlsv1.2 -sSf https://get.k0s.sh | sudo sh
sudo k0s start
```

**Автоматическое:** через **Autopilot** (встроенный):
- Plan CRD: `k0supdate` или `airgapupdate` команды
- SHA256-верификация загружаемых бинарников
- Контроллеры обновляются **последовательно** (concurrent=1 всегда)
- Воркеры обновляются **после ВСЕХ контроллеров**
- Кворум-проверка перед обновлением воркеров
- Автоматические планы через UpdateConfig (cron/periodic)
- Публичный update-сервер: `https://updates.k0sproject.io/`
- Каналы: `stable`, `unstable`

**k0sctl обновление кластера:**
```yaml
spec:
  k0s:
    version: v1.36.3+k0s.2
```
```bash
k0sctl apply  # обновит контроллеры по одному, воркеры batches по 10%
```

### Вердикт

k0s **значительно лучше** по автообновлениям: встроенный Autopilot с верификацией, кворум-проверками, и строгим порядком (контроллеры → воркеры). K3s требует отдельной установки system-upgrade-controller, который менее «встроенный» но также функционален.

---

## 9. Безопасность

### CIS Benchmark

**K3s:**
- Проходит **многие** CIS-контролы по умолчанию
- Режим `--profile=cis` для hardened-конфигурации
- Требуются ручные настройки: kernel parameters (`vm.panic_on_oom=0`, `vm.overcommit_memory=1`, `kernel.panic=10`), EventRateLimit admission, AlwaysPullImages, audit logging, secrets encryption, PSA
- Secrets encryption: `--secrets-encryption` (provider: aescbc)
- TLS cipher suites по CIS-требованиям (ECDHE+AES-GCM/ChaCha20)
- Network policy logging через NFLOG

**k0s:**
- CI-тестирован с **kube-bench** (`k0s-1.0` benchmark)
- **15 проверок отключены** по умолчанию:
  - Master: audit logging (4 проверки), encryption provider (2), EventRateLimit, AlwaysPullImages
  - Worker: kubelet service file (2), protect-kernel-defaults, TLS auto-rotation
  - Control plane: client cert auth, audit policy (2)
- Причины отключения: «оставлено на усмотрение пользователя» или особенности архитектуры

### Сертификаты

| | K3s | k0s |
|---|---|---|
| CA cert | 10 лет, не автообновляется | 10 лет (настраивается), не автообновляется |
| Server cert | 365 дней, автообновление | 87600h (10 лет) по умолчанию (настраивается через `ca.certificatesExpireAfter`) |
| TLS SAN security | `--tls-san-security=true` (защита SAN) | Через `spec.api.sans` |

**Важно:** В обоих случаях client-сертификаты **невозможно отозвать** (общее ограничение Kubernetes).

### Дополнительно

| Возможность | K3s | k0s |
|---|---|---|
| SELinux | ✅ `--selinux` | ✅ |
| Pod Security Standards | ✅ (через admission config) | ✅ |
| Signed binaries | ❌ | ✅ |
| Rootless mode | ✅ (экспериментально, cgroup v2 only) | ❌ |
| CIS profile | ✅ `--profile=cis` | 🔧 kube-bench + ручная настройка |

---

## 10. Helm-интеграция

### K3s — helm-controller

- **HelmChart CRD** в `kube-system`
- Автодеплой из `/var/lib/rancher/k3s/server/manifests/`
- Precedence: chart defaults → HelmChart valuesContent → HelmChartConfig valuesContent → `spec.set`
- Поддержка: OCI реестры, basic auth, mTLS, Bootstrap charts
- helm-controller настраивается через `helm-controller-arg` (v1.36.3+k3s1+)

### k0s — Chart CRD

- API: `helm.k0sproject.io/v1beta1`
- **Рекомендуемый способ:** Chart CRD в namespace `kube-system`
- Альтернатива: `spec.extensions.helm` в k0s.yaml (repositories + charts)
- Поддержка: OCI реестры, secret-based auth, mTLS
- Default options: `--create-namespace`, `--atomic`, `--force` (upgrade), `--wait`, `--wait-for-jobs`
- **Не требует перезапуска** k0s при добавлении/изменении Chart

### Вердикт

Оба имеют полноценную Helm-интеграцию через CRD. k0s не требует перезапуска при изменениях; K3s через manifests-директорию — менее гибко, но проще для понимания.

---

## 11. HA (высокая доступность)

### K3s

**Два варианта:**

1. **Embedded etcd** (`--cluster-init`): 3/5/7 серверов, кворум автоматический
2. **Внешняя БД** (MySQL/PostgreSQL/etcd): 2+ серверов, фиксированный registration address

- Для HA нужен **внешний Load Balancer** перед API-серверами (HAProxy, nginx, cloud LB)
- `--tls-san` для добавления адресов LB в TLS-сертификат
- Серверы обновляются **по одному**
- Автоматические snapshot'ы etcd с S3-бэкапом

### k0s

- Embedded etcd (по умолчанию), кластер из контроллеров
- **Встроенный Keepalived** для control-plane LB (VRRP + Virtual Server)
- Конфигурация VRRP: virtualIPs, interface, virtualRouterID, unicast peers, lbAlgo (rr/wrr/lc/wlc/...), lbKind (DR/NAT/TUN)
- Конфигурация Keepalived полностью кастомизируется через шаблоны (configTemplateVRRP, configTemplateVS)
- Shared CA certificates между контроллерами (ручное копирование)
- Внешний LB (HAProxy) тоже поддерживается как альтернатива Keepalived
- `k0sctl` автоматизирует HA-upgrade

### Вердикт

k0s **выигрывает** во встроенном control-plane LB (Keepalived) — не нужен внешний HAProxy для простых сценариев. K3s требует внешний LB, но имеет более成熟ную автоматизацию snapshot'ов и миграции.

---

## 12. Air-gap установка

### K3s

- Копирование бинарника + images tar в `/var/lib/rancher/k3s/agent/images/`
- `INSTALL_K3S_SKIP_DOWNLOAD=true ./install.sh`
- Встроенный **Spegel** (distributed OCI registry) — кэширование образов между нодами
- Условный импорт: `.cache.json` для импорта только изменённых tarballs
- SELinux: нужен предварительный `k0s-selinux` RPM

### k0s

- OCI-архивы (tarball OCI Image Layout) в `/var/lib/k0s/images/`
- k0s автоматически импортирует из этой директории
- Pre-built bundles на GitHub releases
- `k0s airgap list-images` + `k0s airgap bundle-artifacts` для создания собственных bundles
- k0sctl: файлы загружаются на ноды через SSH (`files:` в конфиге)
- `default_pull_policy: Never` для полного отключения pull'а
- Loose platform matching: на arm/v8 импортируются arm/v7, v6, v5

### Вердикт

Оба поддерживают air-gap. K3s имеет Spegel (встроенный распределённый registry) — удобно для кэширования образов. k0s использует OCI-архивы и более простую модель (положил файл — k0s подхватит).

---

## 13. Мониторинг и observability

### K3s

- Все компоненты логируются в stdout (systemd-journald)
- Метрики kubelet/kube-proxy доступны стандартно (10249, 10250)
- Для продвинутого мониторинга нужен kube-prometheus-stack (отдельно)

### k0s

- **Opt-in metrics scraper**: `k0s install controller --enable-metrics-scraper`
  - Deploys `k0s-pushgateway` в `k0s-system`
  - Scraped: scheduler, controller-manager, etcd, kine
  - ServiceMonitor для Prometheus Operator в комплекте
- Telemetry включена по умолчанию (10-минутный интервал, отправляется в Mirantis)
- Отключение: `spec.telemetry.enabled: false`

---

## 14. Масштабирование и sizing

### K3s

- Таблица sizing для серверов и внешних БД (до 500+ нод)
- ДляHA: 3 сервера масштабируют ~50% больше агентов
- Внешняя БД: 1 vCPU/2 GB до 10 нод, 16 vCPU/64 GB для 500+ нод

### k0s

- Масштабирование: до 5,000 воркеров / 150,000 подов на контроллере (32-64 GB RAM)
- etcd: рекомендовано 3 или 5 контроллеров для HA
- Worker nodes: минимум 15% свободного диска

---

## 15. Ограничения и known issues

### K3s

| Ограничение | Описание |
|---|---|
| SQLite | Только single-server, не для HA |
| Traefik по умолчанию | Может конфликтовать если нужен другой ingress |
| Rancher-специфика | HelmChart CRD — специфический формат |
| Windows | Не поддерживается |
| Network policy | Не поддерживает policies с пустым `podSelector` |
| Single-process | Все компоненты разделяют конфиг логирования |
| iptables cleanup | При отключении netpol нужно `k3s-killall.sh` |
| Миграция SQLite→etcd | Односторонняя, откат невозможен |

### k0s

| Ограничение | Описание |
|---|---|
| Нет ingress/LB/storage из коробки | Больше ручной работы при настройке |
| Смена CNI | **Требует полного пересоздания кластера** |
| Уменьшение etcd | **Невозможно** — ручное удаление ноды перед выключением |
| k0sctl | Не может **удалять** ноды, только добавлять |
| Client certs | Невозможно отозвать (Kubernetes limitation) |
| CIS benchmark | 15 проверок отключены (audit, encryption, AlwaysPullImages) |
| Windows | Экспериментально |
| iptables version | Конфликты между bundled и host версиями |
| Firewalld | Несовпадение backend (nftables vs iptables) ломает сеть |
| nftables kube-proxy | Требует версию container nftables ≤ host (segfault иначе) |
| ControlNode CRD | Не автоудаляются при исчезновении контроллера |
| Контроллеры | На контроллерах **нет kubelet** — нельзя запускать workload на control-plane нодах (по дизайну) |
| Телеметрия | Включена по умолчанию (отправляется в Mirantis) |

---

## 16. Экосистема и сообщество

| | K3s | k0s |
|---|---|---|
| GitHub Stars | 33.8k | 6.5k |
| Контрибьюторы | 5,689 | 1,569 |
| CNCF Sandbox | с авг 2020 (~6 лет) | с янв 2025 (~1.5 года) |
| Slack | Rancher #k3s + CNCF #k3s | Kubernetes #k0sproject |
| Community meetings | Bi-weekly (EMEA + APAC) | Office hours (EU + US) |
| Terraform | `rancher2` + community providers | Внутренний (OpenTofu для тестов) |
| Ansible | Множество community roles | Официальный playbook в доках |
| Документация | Обширная, много community-туториалов | Хорошая, меньше community-контента |
| Backing | SUSE/Rancher (крупная компания) | Mirantis (купившая Docker Enterprise) |

### Версии Kubernetes

Оба следуют upstream Kubernetes非常 близко:
- K3s: патчи в течение 1 недели, миноры в течение 30 дней
- k0s: аналогичный темп, плюс альфа-сборки для следующих миноров

Поддерживаемые ветки (авг 2026): оба поддерживают 1.33, 1.34, 1.35, 1.36.

---

## 17. Размер бинарника

| | K3s | k0s |
|---|---|---|
| Бинарник | ~78 MB | ~250 MB |
| Air-gap bundle | ~233-253 MB | ~331-401 MB |

K3s значительно меньше за счёт удаления in-tree storage/cloud providers.

---

## 18. Установка и первичная настройка

### K3s — однострочник

```bash
# Server (single-node)
curl -sfL https://get.k3s.io | sh -

# Agent
curl -sfL https://get.k3s.io | K3S_URL=https://server:6443 K3S_TOKEN=<token> sh -

# Получить kubeconfig
cat /etc/rancher/k3s/k3s.yaml
```

### k0s — однострочник

```bash
# Controller
curl -sSLf https://get.k0s.io | sudo sh

# Worker
k0s token create --role=worker > /tmp/token
# Скопировать токен на worker
sudo k0s install worker --token-file /tmp/token && sudo k0s start

# Kubeconfig
sudo k0s kubeconfig create > ~/.kube/config
```

Для multi-node кластеров:
- K3s: ручная настройка через env-переменные (K3S_URL, K3S_TOKEN)
- k0s: **k0sctl** (SSH-based кластер-менеджер): `k0sctl init` → редактирование → `k0sctl apply`

---

## 19. Когда выбирать что

| Сценарий | Рекомендация | Почему |
|---|---|---|
| **Single-node homelab, весь стек из коробки** | **K3s** | Ingress + LB + storage + helm из коробки |
| **Минимальный контроллер, гибкость в выборе компонентов** | **k0s** | 1 GB RAM контроллер,自治 CNI выбор |
| **Multi-node кластер с простым HA** | **k0s** | Встроенный Keepalived, не нужен внешний LB |
| **Автоматические обновления** | **k0s** | Autopilot встроен, K3s требует system-upgrade-controller |
| **Edge/IoT/ARM** | **K3s** | Меньше бинарник, ARMv6 поддержка, Spegel registry |
| **Windows-воркеры** | **k0s** | Экспериментально, но поддерживается |
| **CI/CD и pipeline** | **K3s** | Быстрый старт, k3d (Docker-in-Docker) |
| **Enterprise/Mirantis-экосистема** | **k0s** | Интеграция с k0rdent, MKE |
| **CIS-hardened по умолчанию** | **K3s** | `--profile=cis` из коробки |
| **Встроенный backup/restore** | **k0s** | `k0s backup` / `k0s restore` |
| **Внешние БД (MySQL/PostgreSQL)** | **K3s** | kine поддерживает diverse БД |
| **RISC-V архитектура** | **k0s** | Поддержка (без пребилдов) |

---

## 20. Итоговая матрица сравнения

| Критерий | K3s | k0s | Преимущество |
|---|---|---|---|
| Min RAM controller | 2 GB | 1 GB | **k0s** |
| Ingress из коробки | ✅ Traefik v3 | ❌ | **K3s** |
| LoadBalancer из коробки | ✅ ServiceLB | ❌ | **K3s** |
| Storage из коробки | ✅ local-path | ❌ | **K3s** |
| Helm-интеграция | ✅ | ✅ | Равно |
| Auto-deploy manifests | ✅ | ✅ | Равно |
| CNI по умолчанию | Flannel | Kube-router | Разный стиль |
| CNI alternatives | 🔧 manual | ✅ Calico встроен | **k0s** |
| Control-plane LB | ❌ (внешний) | ✅ Keepalived | **k0s** |
| Node-local LB | ❌ | ✅ EnvoyProxy/Traefik | **k0s** |
| Autopilot (автообновления) | ❌ (system-upgrade-controller) | ✅ встроен | **k0s** |
| Backup/Restore | ❌ (etcdctl) | ✅ CLI | **k0s** |
| Air-gap | ✅ (Spegel) | ✅ (OCI bundles) | Равно |
| CIS benchmark | ✅ `--profile=cis` | 🔧 kube-bench | **K3s** |
| Secrets encryption | ✅ `--secrets-encryption` | ✅ (настройка) | **K3s** проще |
| Rootless mode | ✅ (экспериментально) | ❌ | **K3s** |
| Windows support | ❌ | ✅ (экспериментально) | **k0s** |
| RISC-V | ❌ | ✅ | **k0s** |
| Containerd version | 2.x | 2.x (1.36) / 1.7.x (1.33-1.35) | Равно |
| Datastore flexibility | SQLite/etcd/MySQL/PG | etcd/kine(SQLite/MySQL/PG) | **K3s** (SQLite из коробки) |
| Snapshot'ы etcd | ✅ (авто + S3) | ❌ (вручную) | **K3s** |
| Смена CNI без пересоздания | ✅ (перезапуск) | ❌ (полное пересоздание) | **K3s** |
| Размер бинарника | ~78 MB | ~250 MB | **K3s** |
| Community | 33.8k ⭐ / 5.7k contributors | 6.5k ⭐ / 1.6k contributors | **K3s** |
| CNCF статус | Sandbox (6 лет) | Sandbox (1.5 года) | **K3s** |
| Контроллер без kubelet | ❌ (всё на всех узлах) | ✅ (изоляция control-plane) | **k0s** |

---

## Источники

### K3s

- [docs.k3s.io — Requirements](https://docs.k3s.io/installation/requirements)
- [docs.k3s.io — Packaged Components](https://docs.k3s.io/installation/packaged-components)
- [docs.k3s.io — Datastore](https://docs.k3s.io/datastore)
- [docs.k3s.io — Networking](https://docs.k3s.io/networking/networking-services)
- [docs.k3s.io — Storage](https://docs.k3s.io/storage)
- [docs.k3s.io — Security Hardening Guide](https://docs.k3s.io/security/hardening-guide)
- [docs.k3s.io — HA](https://docs.k3s.io/high-availability)
- [docs.k3s.io — Air-Gap](https://docs.k3s.io/installation/airgap)
- [docs.k3s.io — Configuration](https://docs.k3s.io/installation/configuration)
- [docs.k3s.io — CLI Server](https://docs.k3s.io/cli/server)
- [docs.k3s.io — CLI Agent](https://docs.k3s.io/reference/cli/agent)
- [docs.k3s.io — Advanced](https://docs.k3s.io/advanced)
- [docs.k3s.io — Helm](https://docs.k3s.io/helm)
- [docs.k3s.io — Upgrades](https://docs.k3s.io/upgrade/upgrade)
- [docs.k3s.io — Architecture](https://docs.k3s.io/operational/architecture)
- [github.com/k3s-io/k3s](https://github.com/k3s-io/k3s)

### k0s

- [docs.k0sproject.io — System Requirements](https://docs.k0sproject.io/stable/system-requirements/)
- [docs.k0sproject.io — Architecture](https://docs.k0sproject.io/stable/architecture/)
- [docs.k0sproject.io — Networking](https://docs.k0sproject.io/stable/networking/)
- [docs.k0sproject.io — Configuration](https://docs.k0sproject.io/stable/k0s-configuration/)
- [docs.k0sproject.io — Autopilot](https://docs.k0sproject.io/stable/autopilot/)
- [docs.k0sproject.io — Manifests](https://docs.k0sproject.io/stable/manifests/)
- [docs.k0sproject.io — Helm Charts](https://docs.k0sproject.io/stable/helm-charts/)
- [docs.k0sproject.io — Air-Gap](https://docs.k0sproject.io/stable/airgap-install/)
- [docs.k0sproject.io — Storage](https://docs.k0sproject.io/stable/storage/)
- [docs.k0sproject.io — CIS Benchmark](https://docs.k0sproject.io/stable/cis_benchmark/)
- [docs.k0sproject.io — HA](https://docs.k0sproject.io/stable/high-availability/)
- [docs.k0sproject.io — Lifecycle](https://docs.k0sproject.io/stable/lifecycle/)
- [docs.k0sproject.io — CLI](https://docs.k0sproject.io/stable/cli/)
- [docs.k0sproject.io — Examples](https://docs.k0sproject.io/stable/examples/)
- [docs.k0sproject.io — Windows](https://docs.k0sproject.io/stable/windows/)
- [docs.k0sproject.io — k0sctl](https://docs.k0sproject.io/stable/k0sctl/)
- [docs.k0sproject.io — Monitoring](https://docs.k0sproject.io/stable/monitoring/)
- [github.com/k0sproject/k0s](https://github.com/k0sproject/k0s)
