# Ansible: декларативные пакеты хоста

Декларативно управляет пакетами, группами и сторонними репозиториями хоста
`homelab` (Fedora Server 44). Источник правды — `group_vars/all.yml`.

## Структура

| Файл | Назначение |
| --- | --- |
| `inventory.yml` | Один хост `homelab` с локальным подключением (запуск на самом сервере) |
| `group_vars/all.yml` | Списки пакетов, групп и «запрещённых» пакетов |
| `host.yml` | Плейбук: репозитории → пакеты → группы → чистка |
| `ansible.cfg` | Настройки по умолчанию (инвентарь, читаемый вывод) |

## Запуск (на сервере homelab)

Плейбук выполняется на самом сервере от `artlab`:

```sh
cd /home/artlab/projects/homelab/ansible
ansible-playbook host.yml
```

`become: true` выполняет задачи через `sudo`. Если sudo спрашивает пароль:

```sh
ansible-playbook host.yml --ask-become-pass
```

## Dry-run

Посмотреть, что было бы сделано, ничего не меняя:

```sh
ansible-playbook host.yml --check --diff
```

## Как менять состав

- Добавить пакет — дописать в `host_packages` в `group_vars/all.yml`.
- Запретить пакет — перенести его из `host_packages` в `host_packages_absent`.
- Новая группа — в `host_groups` с префиксом `@` (например `"@development-tools"`).
- Инструмент, которого нет в репозиториях Fedora (CLI операторов, клиенты) —
  отдельная секция в `host.yml` с пином версии и checksum в `group_vars/all.yml`:
  так сделаны `sops`, `kubeseal`, `argocd`, `kubectl-cnpg`.

После правки прогнать плейбук — он идемпотентен, лишние запуски ничего не
ломают.

## Что НЕ делает

- Не удаляет пакеты, которых нет в списке (только явно перечисленные в
  `host_packages_absent`). Полная drift-детекция «убрать всё лишнее» — отдельный
  шаг (systemd-timer + сравнение с `dnf repoquery --userinstalled`).
- Не трогает Docker-контейнеры и Compose-проекты — это другой слой.
- Не включает репозиторий Adoptium: он отключён на сервере, а `java-21-openjdk`
  помечен в списке как кандидат на удаление (остался от Jenkins).

## Требования

- Ansible ≥ 13 (`ansible-core` 2.20) — `dnf5`, `yum_repository` встроены,
  `community.general.copr` входит в пакет `ansible`.
- Целевой хост: Fedora 44 (dnf5).
