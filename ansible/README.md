# Ansible: декларативная подготовка хоста

Декларативно управляет пакетами, репозиториями и системными конфигами хоста
`homelab` (Fedora Server 44). Логика разложена по ролям — одна роль на зону
ответственности; `host.yml` и `agent.yml` остаются тонкими точками входа.

## Структура

| Файл | Назначение |
| --- | --- |
| `inventory.yml` | Один хост `homelab` с локальным подключением (запуск на самом сервере) |
| `group_vars/all.yml` | Общие переменные (`repo_root`); грузится автоматически для группы `all` |
| `host.yml` | Плейбук хоста: список ролей, без задач |
| `agent.yml` | Плейбук: пользователь `ai-agent` и его окружение |
| `roles/` | Роли, по одной на зону ответственности (таблица ниже) |
| `ansible.cfg` | Настройки по умолчанию (инвентарь, `roles_path`, читаемый вывод) |

## Роли

| Роль | Зона ответственности |
| --- | --- |
| `base` | Репозитории dnf, пакеты, группы пакетов, `autoremove` |
| `cli_tools` | `sops`, `vals` (сборка), `kubeseal`, `argocd`, `kubectl-cnpg` |
| `docker` | `/etc/docker/daemon.json` |
| `autoupdates` | `dnf-automatic` (таймер + конфиг) |
| `fail2ban` | `jail.local` |
| `sysctl` | `99-inotify.conf` |
| `tailscale_policy_route` | systemd-юнит policy routing для tailnet |
| `longhorn_prereqs` | `iscsid`, каталог данных, SELinux-модуль |
| `ai_agent` | Пользователь `ai-agent`: dotfiles, `authorized_keys`, sudoers |

Параметры каждой роли — в её `roles/<имя>/defaults/main.yml`, задачи — в
`tasks/`, перезапуски сервисов — в `handlers/`. Источник правды для содержимого
системных конфигов — каталог `etc/`: роли копируют оттуда по
`{{ repo_root }}/etc/...`.

## Запуск (на сервере homelab)

Плейбуки выполняются на самом сервере от `artlab`:

```sh
cd /home/artlab/projects/homelab/ansible

ansible-playbook host.yml     # подготовка хоста
ansible-playbook agent.yml    # окружение ai-agent
```

`become: true` выполняет задачи через `sudo`. Sudo у `artlab` спрашивает пароль,
поэтому нужен `--ask-become-pass` (`-K`):

```sh
ansible-playbook host.yml --ask-become-pass
```

## Dry-run

Посмотреть, что было бы сделано, ничего не меняя:

```sh
ansible-playbook host.yml --check --diff --ask-become-pass
ansible-playbook agent.yml --check --diff --ask-become-pass
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

- Добавить пакет — в `base_packages` (`roles/base/defaults/main.yml`).
- Новая группа пакетов — в `base_groups` с префиксом `@` (например
  `"@development-tools"`).
- Инструмент, которого нет в репозиториях Fedora — пин версии и checksum в
  `roles/cli_tools/defaults/main.yml`, задача установки в
  `roles/cli_tools/tasks/main.yml`: так сделаны `sops`, `vals`, `kubeseal`,
  `argocd`, `kubectl-cnpg`.
- Новый системный конфиг — файл в `etc/`, отдельная роль, копирующая его по
  `{{ repo_root }}/etc/...`, при необходимости handler на перезапуск сервиса.

После правки прогнать плейбук — он идемпотентен, лишние запуски ничего не
ломают.

## Что НЕ делает

- Не удаляет пакеты, которых нет в списке. Полная drift-детекция «убрать всё
  лишнее» — отдельный шаг (systemd-timer + сравнение с
  `dnf repoquery --userinstalled`).
- Не трогает рабочие нагрузки кластера — это другой слой.
- Не включает репозиторий Adoptium: он отключён на сервере, а `java-21-openjdk`
  помечен в списке как кандидат на удаление (остался от Jenkins).

## Требования

- Ansible ≥ 13 (`ansible-core` 2.20) — `dnf5`, `yum_repository` встроены,
  `community.general.copr` входит в пакет `ansible`.
- Целевой хост: Fedora 44 (dnf5).
