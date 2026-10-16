# System configs

Системные конфигурации, хранящиеся в репозитории и копирующиеся в `/etc`
на сервере `homelab` через Ansible (`infra/ansible/host.yml`).

## Развёртывание

Предпочтительный способ — через Ansible с контроллера (macOS):

```sh
cd infra/ansible && ansible-playbook host.yml --ask-become-pass
```

Альтернативно (вручную, для отладки) — с контроллера: файл берётся из рабочей
копии репозитория и уходит на узел через SSH.

```bash
ssh homelab 'sudo tee /etc/docker/daemon.json' < infra/host/etc/docker/daemon.json
ssh homelab 'sudo tee /etc/dnf/automatic.conf' < infra/host/etc/dnf/automatic.conf
ssh homelab 'sudo tee /etc/fail2ban/jail.local' < infra/host/etc/fail2ban/jail.local
ssh homelab 'sudo tee /etc/systemd/system/tailscale-policy-route.service' < infra/host/etc/systemd/tailscale-policy-route.service
ssh homelab 'sudo tee /etc/sysctl.d/99-inotify.conf' < infra/host/etc/sysctl.d/99-inotify.conf

ssh homelab 'sudo systemctl restart docker'
ssh homelab 'sudo systemctl enable --now dnf-automatic.timer'
ssh homelab 'sudo systemctl enable --now fail2ban'
ssh homelab 'sudo systemctl daemon-reload'
ssh homelab 'sudo systemctl enable --now tailscale-policy-route.service'
ssh homelab 'sudo sysctl --system'
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
- `k0s/k0s.yaml` — `ClusterConfig` k0s. Копируется как есть, переменных в
  нём нет. Разворачивает роль `k0s_config`, она же рестартует
  `k0scontroller` — `spec.api` не обновляется динамически.
