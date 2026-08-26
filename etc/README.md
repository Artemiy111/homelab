# System configs

Системные конфигурации, хранящиеся в репозитории и подключаемые симлинками
в `/etc` на сервере `homelab`.

## Развёртывание

После `git pull --ff-only` на сервере создать симлинки:

```bash
# На сервере (от root или через sudo):
sudo ln -sf /home/artlab/projects/homelab/etc/dnf/automatic.conf /etc/dnf/automatic.conf
```

Включить таймер:

```bash
sudo systemctl enable --now dnf-automatic.timer
```

## Состав

- `dnf/automatic.conf` — конфигурация `dnf-automatic`: только обновления
  безопасности (`upgrade_type = security`), автоматическая установка
  (`apply_updates = yes`), задержка 360 сек для равномерной нагрузки.
