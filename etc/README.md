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

sudo systemctl restart docker
sudo systemctl enable --now dnf-automatic.timer
sudo systemctl enable --now fail2ban
```

## Состав

- `docker/daemon.json` — настройки Docker daemon (ограничение логов: 10 МБ, 3 файла).
- `dnf/automatic.conf` — конфигурация `dnf-automatic`: только обновления
  безопасности (`upgrade_type = security`), автоматическая установка
  (`apply_updates = yes`), задержка 360 сек для равномерной нагрузки.
- `fail2ban/jail.local` — конфигурация `fail2ban`: защита SSH (3 попытки,
  бан на 24 часа), автоматические обновления через firewallcmd-rich-rules.
