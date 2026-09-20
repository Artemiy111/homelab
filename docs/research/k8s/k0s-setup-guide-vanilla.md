# Установка k0s на Fedora Server: гайд «максимально близко к ванильному Kubernetes»

Дата исследования: 2026-08-27.

## Зачем k0s, а не kubeadm

kubeadm — это «vanilla Kubernetes»: каждый компонент отдельно, ручная настройка
CNI, ingress, storage. Это идеально для понимания, но трудоёмко.

k0s даёт **тот же Kubernetes**, но:
- etcd из коробки (как в ванильном)
- Один бинарник вместо 10 пакетов
- Контроллер **без kubelet** (изоляция control-plane — как в production-кластерах)
- kube-proxy с полной поддержкой (iptables/ipvs/nftables/userspace)

Чтобы k0s был «максимально стандартным», нужно:
1. Выбрать **Calico** вместо kube-router (ближе к production)
2. Не использовать k0s-специфичные фичи (autopilot, встроенный LB)
3. Ставить компоненты «как в vanilla»: MetalLB, ingress-nginx, local storage

---

## Шаг 1. Подготовка Fedora

### firewalld — проверить backend

k0s **автоматически** выбирает `nftables` (или `iptables`). firewalld **должен**
использовать тот же backend, иначе kube-proxy/kube-router/Calico будут программировать
правила в неправильном backend → сеть не работает.

```bash
# Проверить текущий backend
grep FirewallBackend /etc/firewalld/firewalld.conf

# Если стоит iptables, а k0s выбрал nftables (или наоборот) — поменять:
sudo sed -i 's/FirewallBackend=iptables/FirewallBackend=nftables/' /etc/firewalld/firewalld.conf
sudo systemctl restart firewalld
```

### SELinux — установить container-selinux

```bash
sudo dnf install -y container-selinux policycoreutils-python-utils
```

### Открыть порты для k0s

Создать service-определения:

```bash
# Controller ports
sudo tee /etc/firewalld/services/k0s-controller.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>k0s-controller</short>
  <description>k0s controller node</description>
  <port protocol="tcp" port="2380" />
  <port protocol="tcp" port="6443" />
  <port protocol="tcp" port="8132" />
  <port protocol="tcp" port="9443" />
</service>
EOF

# Worker ports
sudo tee /etc/firewalld/services/k0s-worker.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>k0s-worker</short>
  <description>k0s worker node</description>
  <port protocol="tcp" port="179" />
  <port protocol="udp" port="4789" />
  <port protocol="tcp" port="10250" />
</service>
EOF
```

Применить (single-node controller+worker — оба сервиса):

```bash
sudo firewall-cmd --permanent --add-service=k0s-controller
sudo firewall-cmd --permanent --add-service=k0s-worker
sudo firewall-cmd --permanent --add-masquerade
sudo firewall-cmd --permanent --add-source=10.244.0.0/16   # podCIDR
sudo firewall-cmd --permanent --add-source=10.96.0.0/12    # serviceCIDR
sudo firewall-cmd --reload
```

---

## Шаг 2. Конфигурация k0s

### Создать конфиг

```bash
mkdir -p /etc/k0s
k0s config create > /etc/k0s/k0s.yaml
```

### Отредактировать: Calico вместо kube-router

```bash
sudo tee /etc/k0s/k0s.yaml << 'EOF'
apiVersion: k0s.k0sproject.io/v1beta1
kind: ClusterConfig
metadata:
  name: k0s
spec:
  api:
    port: 6443

  network:
    provider: calico
    podCIDR: 10.244.0.0/16
    serviceCIDR: 10.96.0.0/12
    calico:
      mode: vxlan
      overlay: Always
      wireguard: false
    kubeProxy:
      disabled: false
      mode: iptables

  storage:
    type: etcd

  telemetry:
    enabled: false
EOF
```

**Почему Calico, а не kube-router:**
- Calico используется в большинстве production-кластеров
- Поддержка network policies на уровне подов (не только namespace)
- WireGuard шифрование между подами
- Поддержка IPVS и nftables в kube-proxy

**Почему iptables, а не ipvs/nftables:**
- iptables — самый стабильный и изученный режим
- ipvs/nftables — новые, могут иметь проблемы на Fedora
- Для homelab iptables достаточно

---

## Шаг 3. Установка

### Установить k0s

```bash
curl --proto '=https' --tlsv1.2 -sSf https://get.k0s.sh | sudo sh
```

### Запустить как controller+worker

```bash
sudo k0s install controller \
  -c /etc/k0s/k0s.yaml \
  --enable-worker \
  --no-taints \
  --start
```

**Флаги:**
- `-c /etc/k0s/k0s.yaml` — путь к конфигу
- `--enable-worker` — запустить kubelet + containerd на этой ноде (можно планировать поды)
- `--no-taints` — убрать taint `node-role.kubernetes.io/control-plane` (иначе поды не встанут без tolerations)
- `--start` — сразу запустить сервис

### Проверить статус

```bash
sudo k0s status
sudo k0s kubectl get nodes
sudo k0s kubectl get pods -A
```

---

## Шаг 4. Настройка kubectl

### Получить kubeconfig

```bash
sudo k0s kubeconfig create > ~/.kube/config
sudo chmod 600 ~/.kube/config
```

### Проверить

```bash
kubectl get nodes
kubectl get pods -A
```

**Важно:** k0s использует свой kubectl через `k0s kubectl`, но с обычным `kubectl`
всё работает если kubeconfig настроен правильно. Используйте `kubectl` — это
стандартный Kubernetes CLI.

---

## Шаг 5. SELinux для k0s

```bash
DATA_DIR="/var/lib/k0s"

# containerd binary
sudo semanage fcontext -a -t container_runtime_exec_t "${DATA_DIR}/bin/containerd.*"
sudo semanage fcontext -a -t container_runtime_exec_t "${DATA_DIR}/bin/runc"
sudo restorecon -R -v ${DATA_DIR}/bin

# containerd data
sudo semanage fcontext -a -t container_var_lib_t "${DATA_DIR}/containerd(/.*)?"
sudo semanage fcontext -a -t container_ro_file_t "${DATA_DIR}/containerd/io.containerd.snapshotter.*/snapshots(/.*)?"
sudo restorecon -R -v ${DATA_DIR}/containerd

# CNI
sudo semanage fcontext -a -t container_file_t "/etc/cni/.*"
sudo restorecon -R -v /etc/cni
```

Включить SELinux в containerd:

```bash
sudo mkdir -p /etc/k0s/containerd.d
sudo tee /etc/k0s/containerd.d/selinux.toml << 'EOF'
[plugins.'io.containerd.cri.v1.runtime']
  enable_selinux = true
EOF
```

---

## Шаг 6. Стандартные компоненты

### 6.1. MetalLB (LoadBalancer для bare-metal)

MetalLB реализует тип Service `LoadBalancer` без облачного провайдера.

Открыть порт:

```bash
sudo firewall-cmd --permanent --add-port=7946/tcp
sudo firewall-cmd --permanent --add-port=7946/udp
sudo firewall-cmd --reload
```

Установить через Helm Chart CRD:

```bash
sudo tee /var/lib/k0s/manifests/metallb.yaml << 'EOF'
apiVersion: helm.k0sproject.io/v1beta1
kind: Chart
metadata:
  name: metallb
  namespace: kube-system
spec:
  chartName: metallb/metallb
  version: "0.15.3"
  namespace: metallb-system
  repository:
    url: https://metallb.github.io/metallb
EOF
```

Настроить IP-пул (после деплоя MetalLB):

```bash
kubectl apply -f - << 'EOF'
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lan-pool
  namespace: metallb-system
spec:
  addresses:
    - <metallb-pool>
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: lan-advertisement
  namespace: metallb-system
EOF
```

### 6.2. Ingress-nginx (Ingress Controller)

Установить:

```bash
sudo tee /var/lib/k0s/manifests/nginx-ingress.yaml << 'EOF'
apiVersion: helm.k0sproject.io/v1beta1
kind: Chart
metadata:
  name: ingress-nginx
  namespace: kube-system
spec:
  chartName: ingress-nginx/ingress-nginx
  version: "4.12.1"
  namespace: ingress-nginx
  repository:
    url: https://kubernetes.github.io/ingress-nginx
  values: |
    controller:
      service:
        type: LoadBalancer
EOF
```

Сделать default IngressClass:

```bash
kubectl -n ingress-nginx annotate ingressclasses nginx \
  ingressclass.kubernetes.io/is-default-class="true"
```

Открыть порты:

```bash
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --reload
```

### 6.3. Longhorn (distributed storage)

Установить iSCSI (нужен для Longhorn):

```bash
sudo dnf install -y iscsi-initiator-utils
sudo systemctl enable --now iscsid
```

Установить Longhorn:

```bash
sudo tee /var/lib/k0s/manifests/longhorn.yaml << 'EOF'
apiVersion: helm.k0sproject.io/v1beta1
kind: Chart
metadata:
  name: longhorn
  namespace: kube-system
spec:
  chartName: longhorn/longhorn
  version: "1.10.1"
  namespace: longhorn-system
  repository:
    url: https://charts.longhorn.io
  values: |
    defaultSettings:
      defaultReplicaCount: 1
EOF
```

**Важно для single-node:** `defaultReplicaCount: 1` — иначе Longhorn будет ждать
3 реплики и поды не запустятся.

Сделать default StorageClass:

```bash
kubectl patch storageclass longhorn -p \
  '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### 6.4. Metrics Server (уже есть)

Metrics Server **уже установлен** в k0s. Проверить:

```bash
kubectl top nodes
kubectl top pods -A
```

### 6.5. CoreDNS (уже есть)

CoreDNS **уже установлен** в k0s. Проверить:

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl run dns-test --image=busybox --rm -it -- nslookup kubernetes.default
```

---

## Шаг 7. Проверка кластера

```bash
# Ноды
kubectl get nodes -o wide

# Все поды
kubectl get pods -A

# StorageClass
kubectl get storageclass

# IngressClass
kubectl get ingressclass

# MetalLB
kubectl -n metallb-system get pods
kubectl get IPAddressPool -A

# Logs
sudo k0s logs --tail 50
```

---

## Шаг 8. Что у вас есть vs vanilla Kubernetes

| Компонент | Vanilla K8s | k0s (наш стек) | Отличия |
|---|---|---|---|
| **API Server** | kube-apiserver | kube-apiserver | Идентично |
| **etcd** | etcd | etcd | Идентично |
| **Scheduler** | kube-scheduler | kube-scheduler | Идентично |
| **Controller Manager** | kube-controller-manager | kube-controller-manager | Идентично |
| **kubelet** | kubelet | kubelet | Идентично (на worker'е) |
| **containerd** | containerd | containerd | Идентично |
| **CNI** | Calico/Flannel/Cilium | Calico | Идентично |
| **CoreDNS** | CoreDNS | CoreDNS | Идентично |
| **Metrics Server** | metrics-server | metrics-server | Идентично |
| **kube-proxy** | kube-proxy | kube-proxy | Идентично |
| **Ingress** | ingress-nginx | ingress-nginx | Идентично |
| **LoadBalancer** | MetalLB | MetalLB | Идентично |
| **Storage** | Longhorn/local-path | Longhorn | Идентично |

**Единственные отличия от vanilla:**
1. **Konnectivity** — k0s использует для связи контроллер-воркер (вместо прямого подключения). Не влияет на поведение.
2. **Manifest deployer** — k0s watches `/var/lib/k0s/manifests/` (вместо static pods через kubeadm). Функционально аналогично.
3. **k0s API** — дополнительный порт 9443 для кластерного join. Не влияет на Kubernetes API.

**Всё остальное — standard Kubernetes.**

---

## Шаг 9. Управление

### Старт/стоп

```bash
sudo k0s start
sudo k0s stop
```

### Логи

```bash
sudo journalctl -u k0s -f
sudo k0s logs --tail 100
```

### Сброс (начать заново)

```bash
sudo k0s stop
sudo k0s reset
sudo reboot  # обязательно — iptables правила сохраняются
```

### Бэкап

```bash
sudo k0s backup -o /tmp/k0s-backup.tar.gz
```

### Восстановление

```bash
sudo k0s restore /tmp/k0s-backup.tar.gz
```

### Обновление k0s

```bash
sudo k0s stop
curl --proto '=https' --tlsv1.2 -sSf https://get.k0s.sh | sudo sh
sudo k0s start
```

---

## Шпаргалка по портам (финальная)

```bash
# Весь набор для single-node k0s + Calico + MetalLB + nginx
sudo firewall-cmd --permanent \
  --add-service=k0s-controller \
  --add-service=k0s-worker \
  --add-masquerade \
  --add-source=10.244.0.0/16 \
  --add-source=10.96.0.0/12 \
  --add-port=7946/tcp \
  --add-port=7946/udp \
  --add-port=80/tcp \
  --add-port=443/tcp
sudo firewall-cmd --reload
```

---

## Источники

- [docs.k0sproject.io — Install](https://docs.k0sproject.io/stable/install/)
- [docs.k0sproject.io — Networking](https://docs.k0sproject.io/stable/networking/)
- [docs.k0sproject.io — Calico](https://docs.k0sproject.io/stable/calico/)
- [docs.k0sproject.io — k0s-configuration](https://docs.k0sproject.io/stable/k0s-configuration/)
- [docs.k0sproject.io — Examples (MetalLB, NGINX, Longhorn)](https://docs.k0sproject.io/stable/examples/)
- [docs.k0sproject.io — Air-Gap](https://docs.k0sproject.io/stable/airgap-install/)
- [docs.k0sproject.io — CIS Benchmark](https://docs.k0sproject.io/stable/cis_benchmark/)
