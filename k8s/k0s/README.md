# k0s Kubernetes

Single-node k0s на Fedora Server 44, максимально близкий к vanilla Kubernetes.

## Стек

| Компонент | Версия | Статус |
|---|---|---|
| k0s | latest | Из коробки |
| etcd | embedded | Из коробки |
| Calico | latest | В k0s.yaml |
| kube-proxy | iptables | В k0s.yaml |
| CoreDNS | latest | Из коробки |
| Metrics Server | latest | Из коробки |

## Установка

### Через скрипт (автоматически)

```bash
sudo bash k8s/k0s/install.sh
```

Скрипт сделает:
1. Установит k0s binary
2. Настроит firewalld (порты + pod/service CIDR)
3. Настроит SELinux (container-selinux + labels)
4. Установит k0s с Calico CNI
5. Настроит kubectl

### Вручную

```bash
# Установить k0s
curl --proto '=https' --tlsv1.2 -sSf https://get.k0s.sh | sudo sh

# Настроить firewalld
sudo cp k8s/k0s/firewalld/*.xml /etc/firewalld/services/
sudo firewall-cmd --permanent --add-service=k0s-controller --add-service=k0s-worker --add-masquerade --add-source=10.244.0.0/16 --add-source=10.96.0.0/12
sudo firewall-cmd --reload

# Установить k0s
sudo k0s install controller -c /etc/k0s/k0s.yaml --enable-worker --no-taints --start

# Kubeconfig
sudo k0s kubeconfig create > ~/.kube/config
chmod 600 ~/.kube/config
```

## Проверка

```bash
kubectl get nodes
kubectl get pods -A
kubectl get storageclass
```

## Управление

```bash
# Статус
sudo k0s status

# Логи
sudo journalctl -u k0s -f

# Старт/стоп
sudo k0s start
sudo k0s stop

# Сброс (начать заново)
sudo k0s stop && sudo k0s reset && sudo reboot

# Бэкап
sudo k0s backup -o /tmp/k0s-backup.tar.gz

# Обновление
sudo k0s stop && curl -sSLf https://get.k0s.sh | sudo sh && sudo k0s start
```

## Структура файлов

```
k8s/k0s/
├── k0s.yaml                          # Main config (Calico, etcd)
├── install.sh                        # Installation script
├── firewalld/
│   ├── k0s-controller.xml            # Controller ports
│   └── k0s-worker.xml                # Worker ports
├── selinux/
│   └── containerd-selinux.toml       # SELinux for containerd
└── README.md                         # This file
```

## Дальнейшие шаги

После установки k0s:
1. Calico уже работает (в конфиге)
2. MetalLB — LoadBalancer для bare-metal
3. ingress-nginx — Ingress controller
4. Longhorn — distributed storage (опционально)

См. `docs/research/k8s/k0s-setup-guide-vanilla.md` для деталей.

## Источники

- [docs.k0sproject.io](https://docs.k0sproject.io/)
- [docs/research/k8s/k0s-kubernetes-distribution.md](../../docs/research/k8s/k0s-kubernetes-distribution.md)
- [docs/research/k8s/k3s-vs-k0s-detailed-comparison.md](../../docs/research/k8s/k3s-vs-k0s-detailed-comparison.md)
