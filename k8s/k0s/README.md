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
           → Technitium (Docker-контейнер на этом же сервере)
```

**Ловушка:** Technitium крутится в Docker. Если Docker остановлен — DNS мертв,
и k0s не может скачать образы. Решения:

1. Поднять k0s **до** остановки Docker (Technitium ещё жив), либо
2. Временно прописать на роутере upstream DNS `1.1.1.1` вместо форварда на Technitium, либо
3. Запустить Technitium отдельно от Docker (напрямую на хосте).

Проверка до установки:

```bash
getent hosts quay.io      # должен вернуть IP
```

## ⚠️ Совместимость с Docker

k0s и Docker **оба** пишут правила в nftables. При одновременной работе возможен
конфликт (сотни «чужих» правил ломают сеть pod'ов).

**Порядок запуска (важно):**
1. Запустить k0s: `sudo k0s start`
2. Дождаться `kubectl get pods -A` (все Running)
3. Только потом запускать Docker: `sudo systemctl start docker`

Если сеть k0s сломалась из-за правил Docker, почистить nftables:

```bash
sudo nft flush ruleset
sudo k0s stop && sudo k0s start
```

> Полный сброс (всё заново): `sudo k0s stop && sudo k0s reset && sudo reboot`

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

## Дальнейшие шаги

После установки k0s (Calico уже поднят из k0s.yaml):
1. MetalLB — LoadBalancer для bare-metal
2. ingress-nginx — Ingress controller
3. Longhorn — distributed storage (опционально)

См. `docs/research/k8s/k0s-setup-guide-vanilla.md` для деталей.

## Источники

- [docs.k0sproject.io](https://docs.k0sproject.io/)
- [docs/research/k8s/k0s-kubernetes-distribution.md](../../docs/research/k8s/k0s-kubernetes-distribution.md)
- [docs/research/k8s/k3s-vs-k0s-detailed-comparison.md](../../docs/research/k8s/k3s-vs-k0s-detailed-comparison.md)
