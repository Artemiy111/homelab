# k0s Kubernetes

Single-node k0s на Fedora Server 44, максимально близкий к vanilla Kubernetes.

## Стек

| Компонент | Версия | Статус |
|---|---|---|
| k0s | v1.36.3+k0s.2 | Из коробки |
| etcd | embedded | Из коробки |
| Calico | v3.32.1 | В k0s.yaml (vxlan) |
| kube-proxy | iptables | В k0s.yaml (nftables через iptables-nft) |
| CoreDNS | latest | Из коробки |
| Metrics Server | latest | Из коробки |

> Версия k0s фиксируется в `k0s.yaml` не явно, а ставится через `get.k0s.sh`.
> Актуальную версию на сервере: `k0s version`.

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
sudo k0s kubeconfig admin create > ~/.kube/config
chmod 600 ~/.kube/config
```

## Проверка

```bash
kubectl get nodes
kubectl get pods -A
kubectl get storageclass
```

## ⚠️ DNS (критично для запуска)

containerd должен резолвить registry (`quay.io`, `registry.k8s.io`) **до** старта
k0s, иначе pod'ы Calico/ключевые компоненты падают в `ImagePullBackOff` с ошибкой:

```
failed to resolve image: ... lookup quay.io: Try again
```

DNS-цепочка на сервере:

```
containerd → systemd-resolved (127.0.0.53) → 192.0.2.10 (Keenetic)
           → 192.0.2.10:53 = Service technitium-dns (externalIPs)
           → pod technitium в кластере (namespace default)
```

**Ловушка (курица и яйцо):** Technitium обслуживается кластером сам, а кластеру DNS
нужен, чтобы тянуть образы. Пока Technitium лежит, хост не резолвит вообще ничего —
включая `git pull`, которым этот же под можно было бы починить. Починить кластер
обычным процессом доставки в этот момент нельзя.

Разбор и варианты решения — issue [#6](https://github.com/Artemiy111/homelab/issues/6).

Проверка до установки:

```bash
getent hosts quay.io      # должен вернуть IP
```

## kubectl

k0s поставляется со своим `kubectl`, который **не умеет** внутреннюю команду
`__complete` — поэтому tab-автодополнение через нативный `kubectl completion`
не работает. Используем алиас + `KUBECONFIG` в окружении (без отдельного
wrapper-файла):

```zsh
# ~/.zshrc
export KUBECONFIG=~/.kube/config
alias kubectl='k0s kubectl'
alias k='kubectl'
```

Для самого `k0s` автодополнение работает:

```zsh
source <(k0s completion zsh)
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

## Состояние кластера

Поверх k0s (Calico уже поднят из k0s.yaml):

| Слой | Где |
|---|---|
| Ingress | Traefik — единый вход на `192.0.2.10` (`k8s/traefik/`) |
| UI кластера | Headlamp (`k8s/headlamp/`) |
| Секреты | sealed-secrets (`k8s/sealed-secrets/`) |
| GitOps | Argo CD — пробный стенд (`k8s/argocd/README.md`); целевое решение — Flux |

### Почему нет MetalLB

LoadBalancer на однонодном кластере не нужен: тот же адрес `192.0.2.10`
отдаётся через `externalIPs` сервиса Traefik (`k8s/traefik/values.yaml`),
а MetalLB в L2-режиме пришлось бы отвечать ARP за отдельный VIP `.253`.

Манифесты удалены 2026-09-15, но восстанавливаются, если появится вторая нода:

```bash
helm install metallb metallb/metallb -n metallb --create-namespace \
  --set frrk8s.enabled=false
```

Пул адресов был `192.0.2.10/32` (IPAddressPool + L2Advertisement).
Вернуть файлы: `git show 0fde47d:k8s/metallb/pool.yaml`.

### Прочее

- Longhorn (распределённое хранилище) на одной ноде смысла не имеет —
  реплики некуда раскладывать. Хранилище сейчас — локальные пути узла.
- См. `docs/research/k8s/k0s-setup-guide-vanilla.md` для деталей по установке.

## Источники

- [docs.k0sproject.io](https://docs.k0sproject.io/)
- [docs/research/k8s/k0s-kubernetes-distribution.md](../../docs/research/k8s/k0s-kubernetes-distribution.md)
- [docs/research/k8s/k3s-vs-k0s-detailed-comparison.md](../../docs/research/k8s/k3s-vs-k0s-detailed-comparison.md)
