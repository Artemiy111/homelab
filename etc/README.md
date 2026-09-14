# System configs

Системные конфигурации, хранящиеся в репозитории и копирующиеся в `/etc`
на сервере `homelab` через Ansible (`ansible/host.yml`).

## Развёртывание

Предпочтительный способ — через Ansible:

```sh
cd ansible && ansible-playbook host.yml
```

Альтернативно (вручную, для отладки):

```bash
# На сервере (от root или через sudo):
sudo cp /home/artlab/projects/homelab/etc/docker/daemon.json /etc/docker/daemon.json
sudo cp /home/artlab/projects/homelab/etc/dnf/automatic.conf /etc/dnf/automatic.conf
sudo cp /home/artlab/projects/homelab/etc/fail2ban/jail.local /etc/fail2ban/jail.local
sudo cp /home/artlab/projects/homelab/etc/systemd/tailscale-policy-route.service /etc/systemd/system/
sudo cp /home/artlab/projects/homelab/etc/sysctl.d/99-inotify.conf /etc/sysctl.d/99-inotify.conf

sudo systemctl restart docker
sudo systemctl enable --now dnf-automatic.timer
sudo systemctl enable --now fail2ban
sudo systemctl daemon-reload
sudo systemctl enable --now tailscale-policy-route.service
sudo sysctl --system
```

## Состав

- `docker/daemon.json` — настройки Docker daemon (ограничение логов: 10 МБ, 3 файла).
- `dnf/automatic.conf` — конфигурация `dnf-automatic`: только обновления
  безопасности (`upgrade_type = security`), автоматическая установка
  (`apply_updates = yes`), задержка 360 сек для равномерной нагрузки.
- `fail2ban/jail.local` — конфигурация `fail2ban`: защита SSH (3 попытки,
  бан на 24 часа), автоматические обновления через firewallcmd-rich-rules.
- `systemd/tailscale-policy-route.service` — правило policy routing, без которого
  ответы LoadBalancer/NodePort к tailnet-клиентам уходят через физический
  интерфейс вместо `tailscale0`. Разбор — в
  `docs/troubleshot/tailscale-k8s-ingress-access.md`.
- `sysctl.d/99-inotify.conf` — число inotify-инстансов на uid (`1024` вместо
  дефолтных `128`): все поды k8s и Docker работают под root и делят один бюджет,
  без этого падают файловые watcher'ы (.NET, node-fs.watch) — проявилось
  в Technitium при переносе на Kubernetes.
