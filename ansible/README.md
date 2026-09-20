# Ansible: декларативные пакеты хоста

Декларативно управляет пакетами, группами и сторонними репозиториями хоста
`homelab` (Fedora Server 44). Источник правды — `group_vars/all.yml`.

## Структура

| Файл | Назначение |
| --- | --- |
| `inventory.yml` | Один хост `homelab` с локальным подключением (запуск на самом сервере) |
| `group_vars/all.yml` | Списки пакетов, групп и «запрещённых» пакетов |
| `host.yml` | Плейбук: репозитории → пакеты → группы → чистка |
| `agent.yml` | Плейбук: пользователь `ai-agent` и его окружение |
| `roles/ai_agent/` | Роль: пользователь, dotfiles, `authorized_keys`, sudoers |
| `ansible.cfg` | Настройки по умолчанию (инвентарь, `roles_path`, читаемый вывод) |

## Запуск (на сервере homelab)

Плейбуки выполняются на самом сервере от `artlab`:

```sh
cd /home/artlab/projects/homelab/ansible

ansible-playbook host.yml     # пакеты хоста
ansible-playbook agent.yml    # окружение ai-agent
```

`become: true` выполняет задачи через `sudo`. Если sudo спрашивает пароль:

```sh
ansible-playbook agent.yml --ask-become-pass
```

## Dry-run

Посмотреть, что было бы сделано, ничего не меняя:

```sh
ansible-playbook host.yml --check --diff
ansible-playbook agent.yml --check --diff
```

## Окружение ai-agent (`agent.yml`)

Роль `ai_agent` создаёт пользователя `ai-agent` (zsh, домашний каталог `0700`),
подключает `.zshrc` симлинком на `dotfiles/ai-agent/.zshrc`, копирует
`authorized_keys` (`0600`) и рендерит `/etc/sudoers.d/ai-agent`
(`NOPASSWD: sudo -u artlab`) из шаблона `templates/sudoers.j2` с проверкой
через `visudo`.

Параметры роли (`ai_agent_user`, `ai_agent_sudo_runas`, шелл, список dotfiles) —
в `roles/ai_agent/defaults/main.yml`. Источник правды для содержимого `.zshrc` и
`authorized_keys` — каталог `dotfiles/ai-agent/`: обновление идёт обычным
`git pull`, повторный прогон роли не нужен.

Генерация ключа и подключение (ручные шаги) — в `dotfiles/README.md`.

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
- Не трогает рабочие нагрузки кластера — это другой слой.
- Не включает репозиторий Adoptium: он отключён на сервере, а `java-21-openjdk`
  помечен в списке как кандидат на удаление (остался от Jenkins).

## Требования

- Ansible ≥ 13 (`ansible-core` 2.20) — `dnf5`, `yum_repository` встроены,
  `community.general.copr` входит в пакет `ansible`.
- Целевой хост: Fedora 44 (dnf5).
