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
| `artlab.yml` | Плейбук: домашний каталог `artlab` (dotfiles) |
| `agent.yml` | Плейбук: пользователь `ai-agent` и его окружение |
| `roles/` | Роли, по одной на зону ответственности (таблица ниже) |
| `ansible.cfg` | Настройки по умолчанию (инвентарь, `roles_path`, читаемый вывод) |
| `.ansible-lint` | Конфиг ansible-lint (профиль `production`), тот же проверятся в CI |

## Роли

| Роль | Зона ответственности |
| --- | --- |
| `base` | Репозитории dnf, пакеты, группы пакетов, `autoremove` |
| `cli_tools` | `vals` (сборка), `argocd`, `kubectl-cnpg`; `sops` и `kubeseal` удаляются |
| `docker` | `/etc/docker/daemon.json` |
| `autoupdates` | `dnf-automatic` (таймер + конфиг) |
| `fail2ban` | `jail.local` |
| `sysctl` | `99-inotify.conf` |
| `tailscale_policy_route` | systemd-юнит policy routing для tailnet |
| `longhorn_prereqs` | `iscsid`, каталог данных, SELinux-модуль |
| `k0s_config` | `ClusterConfig` k0s в `/etc/k0s/k0s.yaml`, рестарт `k0scontroller` |
| `ai_agent` | Пользователь `ai-agent`: dotfiles, `authorized_keys`, sudoers |
| `artlab` | Домашний каталог `artlab`: dotfiles из `infra/dotfiles/` |

Параметры каждой роли — в её `roles/<имя>/defaults/main.yml`, задачи — в
`tasks/`, перезапуски сервисов — в `handlers/`. Переменные и `register` внутри
ролей с префиксом имени роли (`cli_tools_`, `longhorn_prereqs_`, ...): у
Ansible единое глобальное пространство имён переменных, префикс защищает роли
от перезаписи переменных друг друга. Источник правды для содержимого
системных конфигов — каталог `infra/host/etc/`: роли копируют оттуда по
`{{ repo_root }}/infra/host/etc/...`.

## Запуск (на сервере homelab)

Плейбуки выполняются на самом сервере от `artlab`:

```sh
cd /home/artlab/projects/homelab/infra/ansible

ansible-playbook artlab.yml    # dotfiles в домашний каталог, без sudo
ansible-playbook host.yml      # подготовка хоста, нужен sudo
ansible-playbook agent.yml     # окружение ai-agent, нужен sudo
```

`become: true` выполняет задачи через `sudo`. У `host.yml` и `agent.yml` он
задан на уровне плейбука, поэтому sudo спрашивает пароль и нужен
`--ask-become-pass` (`-K`):

```sh
ansible-playbook host.yml --ask-become-pass
```

`artlab.yml` `become` не использует: он пишет в домашний каталог владельца
из `artlab`, поэтому пароль не спрашивается.

## Доставка dotfiles

Dotfiles копируются из `{{ repo_root }}/infra/dotfiles/` в домашний каталог и
не линкуются на рабочую копию репозитория. Симлинк делает домашний каталог
зависимым от того, где лежит репозиторий: переезд каталога в другую локацию
оставляет пользователя с битыми файлами, а копия от этого не зависит.

Цена решения: `git pull` на сервере сам по себе домашний каталог не
обновляет, после него нужен прогон плейбука. Локальные правки файлов на
сервере перезаписываются прогоном — источник правды один.

| Файл | Права | Проверка перед записью |
|---|---|---|
| `~/.bash_profile`, `~/.bashrc` | `0644` | `bash -n` |
| `~/.zshrc` | `0644` | `zsh -n` |
| `~/.gitconfig`, `~/.tmux.conf` | `0644` | нет |
| `~/.ssh/config` | `0600` (каталог `~/.ssh` — `0700`) | нет |

Синтаксическая проверка через `validate` не даёт битому rc-файлу доехать до
домашнего каталога и оставить пользователя без рабочего шелла.

## Одна роль вместо всего плейбука

Тег каждой роли равен её имени, поэтому прогоняется только нужная:

```sh
ansible-playbook host.yml --tags k0s_config --ask-become-pass
ansible-playbook host.yml --list-tags
```

Теги заданы в `host.yml` в секции `roles`. Проверка одной роли идёт и в
`--check --diff` — но `gather_facts` остаётся: факты собираются для плейбука,
а не для роли.

## Dry-run

Посмотреть, что было бы сделано, ничего не меняя:

```sh
ansible-playbook host.yml --check --diff --ask-become-pass
ansible-playbook agent.yml --check --diff --ask-become-pass
ansible-playbook artlab.yml --check --diff
```

## Окружение ai-agent (`agent.yml`)

Роль `ai_agent` создаёт пользователя `ai-agent` (zsh, домашний каталог `0700`),
копирует `.zshrc` из `infra/dotfiles/ai-agent/` (перед записью снимает симлинк
на этом пути, если он есть), копирует `authorized_keys` (`0600`) и рендерит
`/etc/sudoers.d/ai-agent` (`NOPASSWD: sudo -u artlab`) из шаблона
`templates/sudoers.j2` с проверкой через `visudo`.

Параметры роли (`ai_agent_user`, `ai_agent_sudo_runas`, шелл, список dotfiles) —
в `roles/ai_agent/defaults/main.yml`. Источник правды для содержимого `.zshrc` и
`authorized_keys` — каталог `infra/dotfiles/ai-agent/`: после `git pull`
содержимое обновляется повторным прогоном `agent.yml` — копия в домашнем
каталоге сама не меняется.

Генерация ключа и подключение (ручные шаги) — в `infra/dotfiles/README.md`.

## Как менять состав

- Добавить пакет — в `base_packages` (`roles/base/defaults/main.yml`).
- Новая группа пакетов — в `base_groups` с префиксом `@` (например
  `"@development-tools"`).
- Инструмент, которого нет в репозиториях Fedora — пин версии и checksum в
  `roles/cli_tools/defaults/main.yml`, задача установки в
  `roles/cli_tools/tasks/main.yml`: так сделаны `vals`, `argocd`,
  `kubectl-cnpg`.
- Новый системный конфиг — файл в `infra/host/etc/`, отдельная роль, копирующая его по
  `{{ repo_root }}/infra/host/etc/...`, при необходимости handler на перезапуск сервиса.
- Новый dotfile пользователя `artlab` — запись в `artlab_managed_files`
  (`roles/artlab/defaults/main.yml`): путь источника, путь назначения, права и
  необязательная команда проверки. Для `ai-agent` — в `ai_agent_dotfiles`
  (`roles/ai_agent/defaults/main.yml`), там права фиксированы в `0600`.

После правки прогнать плейбук — он идемпотентен, лишние запуски ничего не
ломают.

## Что НЕ делает

- Не удаляет пакеты, которых нет в списке. Полная drift-детекция «убрать всё
  лишнее» — отдельный шаг (systemd-timer + сравнение с
  `dnf repoquery --userinstalled`).
- Не трогает рабочие нагрузки кластера — это другой слой.
- Не включает репозиторий Adoptium: он отключён на сервере, а `java-21-openjdk`
  помечен в списке как кандидат на удаление (остался от Jenkins).

## Линт

CI (`.forgejo/workflows/ansible.yml`) прогоняет ansible-lint 26.8.0 с профилем
`production` (настройки — `.ansible-lint`) на изменениях в `infra/ansible/`. Локально:

```sh
python3 -m venv ~/.venvs/ansible
~/.venvs/ansible/bin/pip install "ansible==12.3.0" "ansible-lint==26.8.0"
cd infra/ansible && ~/.venvs/ansible/bin/ansible-lint --offline
```

`ansible` — полный metapackage: его wheel несёт коллекции, syntax-check
резолвит `community.general.copr` без galaxy. В CI зафиксирован 12.x
(ansible-core 2.19) вместо серверных 13.x (core 2.20): образ раннера даёт
python не новее 3.11, а core 2.20 требует 3.12+; линтуемые правила и `dnf5`
в 2.19 те же.

## Требования

- Ansible ≥ 13 (`ansible-core` 2.20) — `dnf5`, `yum_repository` встроены,
  `community.general.copr` входит в пакет `ansible`.
- Целевой хост: Fedora 44 (dnf5).
