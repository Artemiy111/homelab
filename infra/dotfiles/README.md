# Dotfiles

Каждый файл/каталог здесь повторяет структуру домашнего каталога пользователя
`artlab` на сервере `homelab`. Изменения доставляются обычным git-процессом
(commit → push → `git pull --ff-only` на сервере), после чего файлы копируются
в домашний каталог плейбуком: симлинков на файлы репозитория в домашнем
каталоге нет, поэтому его состояние не зависит от того, где лежит рабочая
копия.

## Развёртывание

```bash
# На сервере:
cd /home/artlab/projects/homelab && git pull --ff-only origin main
cd infra/ansible && ansible-playbook artlab.yml
```

Роль `artlab` копирует файлы, права выставляет явно (dotfiles `0644`,
`.ssh/config` `0600`), а перед записью снимает симлинки на этих путях.
Прогон идемпотентен: файлы, совпадающие с репозиторием, он не трогает.

Правки файлов прямо на сервере перезаписываются следующим прогоном — источник
правды ровно один, репозиторий. Симлинк здесь не подошёл бы именно потому,
что его цель меняется вместе с раскладкой репозитория, а файл в домашнем
каталоге остаётся битым: `git pull` обновляет репозиторий, но не ссылку на
него.

## Состав

- `.zshrc` — конфиг zsh (шелл по умолчанию): история (`SHARE_HISTORY`, без
  дубликатов), автодополнение (`compinit` + меню), prompt с git-веткой
  (`vcs_info`), поиск по истории стрелками, алиасы (`ll`, `la`, `g`, `gs`, `gp`,
  ...), PATH из `~/.local/bin` и `~/.bun/bin`.
- `.tmux.conf` — tmux: prefix `C-b`, mouse on, vi-режим, плагины через tpm
  (`tmux-sensible`, `catppuccin/tmux`). Требует tpm в `~/.tmux/plugins/tpm`;
  установка новых плагинов — `C-b I`.
- `.gitconfig` — имя и email автора коммитов.
- `.ssh/config` — конфиг SSH: GitHub (`IdentityFile ~/.ssh/id_github_from_homelab`)
  и Forgejo (`IdentityFile ~/.ssh/id_homelab-forgejo_from_homelab`, порт `2222`).
  Роль копирует его с `0600` и выставляет `~/.ssh` как `0700`.
- `.bash_profile` / `.bashrc` — fallback для bash-сессий (основной шелл — zsh).

## Пользователь ai-agent

Отдельный пользователь для AI-агента с ограниченными правами. По умолчанию
агент ходит от `ai-agent` и работает в своём namespace. При необходимости
выполнить действия от имени `artlab` (запуск init-скриптов, запись в проект)
агент запрашивает разрешение и использует `sudo -u artlab`.

### Развёртывание

```bash
# На сервере:
cd /home/artlab/projects/homelab/infra/ansible && ansible-playbook agent.yml
```

Плейбук создаёт пользователя, копирует dotfiles, ставит
sudoers-правило. Детали — в `infra/ansible/README.md`.

### Структура

```
infra/dotfiles/ai-agent/
├── .zshrc              # Минимальный конфиг zsh (prompt с префиксом ai-agent)
└── .ssh/
    └── authorized_keys # Restrictions: forwarding запрещён
```

Sudoers-правило (`/etc/sudoers.d/ai-agent`) рендерится из шаблона
`infra/ansible/roles/ai_agent/templates/sudoers.j2`; значения `ai_agent_user` и
`ai_agent_sudo_runas` — в `infra/ansible/roles/ai_agent/defaults/main.yml`.

### Модель доступа

| Действие | Как |
|---|---|
| Обычная работа (чтение, git, docker) | от `ai-agent` |
| Запись в проект | `sudo -u artlab bash -lc "..."` |
| Изменение прав/владельца файлов | Недоступно (нет root) |

### Генерация ключей

```bash
# На локальной машине:
ssh-keygen -t ed25519 -f ~/.ssh/ai-agent-key -C 'ai-agent@homelab'

# Добавить публичный ключ в infra/dotfiles/ai-agent/.ssh/authorized_keys
# Скопировать на сервер:
scp infra/dotfiles/ai-agent/.ssh/authorized_keys homelab:/home/ai-agent/.ssh/
```

## Приватные ключи artlab

Приватные ключи (`~/.ssh/id_github_from_homelab`,
`~/.ssh/id_homelab-forgejo_from_homelab`) создаются на сервере один раз и в
репозиторий не попадают — в git лежат только имена файлов из `.ssh/config`.
Создание:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_github_from_homelab
ssh-keygen -t ed25519 -f ~/.ssh/id_homelab-forgejo_from_homelab
```
