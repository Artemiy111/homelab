# kubespray для кластера `yc`

В репозитории только конфигурация: генератор инвентаря, два файла `group_vars` и
`compose.yaml`. Сам kubespray не клонируется — запускается официальным образом в
контейнере.

## 1. Инвентарь

```sh macOS
./infra/yc/ansible/inventory.py > infra/yc/ansible/inventory.yml
```

Скрипт читает `terraform output nodes`: публичный адрес идёт в `ansible_host` (по
нему ходит Ansible), внутренний — в `ip`/`access_ip` (эти kubespray пишет в
сертификаты и etcd). Только стандартная библиотека Python — ни `jq`, ни PyYAML не
нужны. Все узлы попадают сразу в `kube_control_plane`, `kube_node` и `etcd` —
три control plane, каждый из них одновременно worker. Повторять после пересоздания
узлов: адреса меняются. `inventory.yml` в git не попадает.

Инвентарь — обычный YAML в формате kubespray (`all` → `hosts` + группы
`kube_control_plane`, `kube_node`, `etcd`, `k8s_cluster`, `calico_rr`). Проверить,
что Ansible его понимает, не запуская плейбук: `ansible-inventory -i inventory.yml --list`.

## 2. Проверить доступ

```sh macOS
docker compose -f infra/yc/ansible/compose.yaml run --rm kubespray \
  "ansible -i /inventory/inventory.yml all -m ping"
```

Ждём `pong` от обоих узлов. Это проверяет SSH как `ops` (профиль OS Login
сервисного аккаунта), ключ и sudo через `ansible_become`. `known_hosts` внутри
контейнера пустой на каждый запуск, поэтому старые ключи пересозданных ВМ не
мешают.

## 3. Установка

```sh macOS
docker compose -f infra/yc/ansible/compose.yaml run --rm kubespray
```

Команда сервиса по умолчанию — `ansible-playbook -i /inventory/inventory.yml cluster.yml`.
15–20 минут. Образ только `linux/amd64`, на Apple Silicon он идёт через эмуляцию
(в Docker Desktop должен быть включён Rosetta) — медленнее, на результат не влияет.

## 4. Tailscale на узлах

Узлы подключаются к tailnet тем же инвентарём, что и kubespray, но Ansible для
этого запускается с контроллера (macOS), а не из контейнера: контейнер существует
ради зафиксированного окружения kubespray, а роли `artis3n.tailscale.machine`
нужны только SSH и `python3` на узле. Версия коллекции — в `requirements.yml`.
Плейбук идемпотентен: пакет ставится из репозитория Tailscale, `tailscale up`
вызывается только когда меняются флаги или ключ.

До первого прогона в admin console нужны две вещи:

- OAuth client (Settings → OAuth clients) со scope `auth_keys: write` и
  выбранным тегом `tag:k8s`;
- сам тег `tag:k8s` объявлен в `infra/casa/terraform/tailscale/acl.tf`: для
  OAuth-ключа тег обязателен.

Секрет клиента в репозиторий не попадает и в `compose.yaml` не описывается:

```sh macOS
cd infra/yc/ansible
ansible-galaxy collection install -r requirements.yml
read -rs TS_OAUTH_CLIENT_SECRET && export TS_OAUTH_CLIENT_SECRET
ansible-playbook -i inventory.yml tailscale.yml \
  -e ansible_ssh_private_key_file="<ключ из compose.yaml>"
```

`-e` обязателен: в `group_vars/all/yc.yml` путь к ключу контейнерный
(`/root/.ssh/id_rsa`), он писался под монтирование в `compose.yaml`. `-e`
перекрывает `group_vars`, поэтому с контроллера подставляется путь на macOS.
Коллекция ставится в `~/.ansible/collections` и в репозиторий не попадает.

Проверка:

```sh macOS
tailscale status | grep yc-
tailscale ping yc-d1
ssh <логин OS Login>@yc-d1
```

Что плейбук делает и почему так:

| Решение | Причина |
| --- | --- |
| OAuth-ключ, а не auth key | auth key живёт максимум 90 дней, то есть требует ручной ротации; OAuth secret не истекает, а роль выпускает по нему ключ на час |
| `tailscale_oauth_ephemeral: false` | эфемерный узел удаляется из tailnet, когда offline; control plane должен возвращаться сам |
| `--accept-dns=false` | DNS узла обслуживает systemd-resolved, и MagicDNS не должен менять `resolv.conf` под kubelet и containerd |
| `--hostname={{ inventory_hostname }}` | имена в tailnet совпадают с именами инвентаря (`yc-d1`, ...) |
| `state: latest` | сторонний репозиторий не покрыт `unattended-upgrades`, прогон плейбука — единственный механизм обновления |
| Tailscale SSH не включён | вход остаётся через OpenSSH и OS Login, как раньше |

Key expiry у узлов кластера надо выключить (Machines → узел → Disable key
expiry): иначе через 180 дней все три узла молча выпадают из tailnet. То же
правило уже записано для `homelab` в `apps/casa/tailscale/RUNBOOK.md`.

Ловушка на будущее: как только из tailnet пойдёшь в NodePort/LoadBalancer на
этих узлах, ответы kube-proxy уйдут мимо `tailscale0`. Нужен тот же policy
routing, что на `casa` — юнит
`infra/casa/host/etc/systemd/tailscale-policy-route.service`, разбор в
`docs/troubleshoot/tailscale-k8s-ingress-access.md`. Сейчас юнит не ставится:
пока в кластер ходят по SSH и по адресу балансировщика, правило не требуется.

## 5. kubeconfig

Kubespray кладёт его в `infra/yc/ansible/artifacts/admin.conf` (`artifacts_dir`
внутри inventory-каталога). `server` там указывает на внутренний адрес первого
control plane, снаружи недоступный, — заменяем на имя за балансировщиком:

```sh macOS
sed -i '' 's|server: https://.*|server: https://api.yc.clusters.biplane.casa:6443|' \
  infra/yc/ansible/artifacts/admin.conf

export KUBECONFIG="$PWD/infra/yc/ansible/artifacts/admin.conf"
kubectl get nodes
```

Имя попадает в SAN apiserver через `supplementary_addresses_in_ssl_keys`, так что
TLS сходится. Если локальный DNS ещё отдаёт wildcard Technitium (см.
`infra/yc/terraform/cluster/README.md`), `kubectl` уйдёт на домашний узел —
проверить `dig +short api.yc.clusters.biplane.casa` или временно добавить запись в
`/etc/hosts`.

## 6. Проверка

```sh macOS
kubectl get nodes -o wide
yc load-balancer network-load-balancer get nlb-k8s-vm
nc -vz api.yc.clusters.biplane.casa 6443
```

Цель в `nlb-k8s-vm` переходит в `HEALTHY`, когда на узле поднимается apiserver на
6443 — то есть после прогона все три.

## Что где

| Файл | Зачем |
| --- | --- |
| `compose.yaml` | образ kubespray, монтирование инвентаря и ключа |
| `inventory.py` | генерирует `inventory.yml` из `terraform output` |
| `requirements.yml` | версия коллекции `artis3n.tailscale` для плейбука `tailscale.yml` |
| `tailscale.yml` | установка Tailscale и подключение узлов к tailnet |
| `group_vars/all/yc.yml` | пользователь, путь к ключу внутри контейнера, sudo |
| `group_vars/k8s_cluster/yc.yml` | calico, `podCIDR`/`serviceCIDR`, SAN, локальный kubeconfig |

Диапазоны те же, что в `casa`: `10.244.0.0/16` поды, `10.96.0.0/12` сервисы — они
не пересекаются с подсетями VPC (`10.133.0.0/24`, `10.134.0.0/24`).

Поменять ключ: он указан в двух местах — монтирование в `compose.yaml` и
`ansible_ssh_private_key_file` в `group_vars/all/yc.yml` (путь внутри контейнера).

## Чего здесь нет

- Самого kubespray: берётся образом `quay.io/kubespray/kubespray:v2.32.0`.
- k0s: этот стенд собирается kubespray.
