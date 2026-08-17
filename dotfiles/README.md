# Dotfiles

Каждый файл/каталог здесь повторяет структуру домашнего каталога пользователя
`artlab` на сервере `homelab`. Изменения доставляются обычным git-процессом
(commit → push → `git pull --ff-only` на сервере), после чего файлы подключаются
симлинками в домашний каталог.

## Развёртывание

После `git pull --ff-only` на сервере пересоздать симлинки:

```bash
# На сервере:
for f in .zshrc .tmux.conf .gitconfig .bash_profile .bashrc; do
  ln -sf /home/artlab/projects/homelab/dotfiles/$f ~/$f
done
ln -sf /home/artlab/projects/homelab/dotfiles/.ssh/config ~/.ssh/config
```

## Состав

- `.zshrc` — конфиг zsh (шелл по умолчанию): история (`SHARE_HISTORY`, без
  дубликатов), автодополнение (`compinit` + меню), prompt с git-веткой
  (`vcs_info`), поиск по истории стрелками, алиасы (`ll`, `la`, `g`, `gs`, `gp`,
  ...), PATH из `~/.local/bin` и `~/.bun/bin`.
- `.tmux.conf` — tmux: prefix `C-b`, mouse on, vi-режим, плагины через tpm
  (`tmux-sensible`, `catppuccin/tmux`). Требует tpm в `~/.tmux/plugins/tpm`;
  установка новых плагинов — `C-b I`.
- `.gitconfig` — имя и email автора коммитов.
- `.ssh/config` — конфиг SSH для GitHub (`IdentityFile ~/.ssh/id_lab_github`).
- `.bash_profile` / `.bashrc` — fallback для bash-сессий (основной шелл — zsh).

## Пользователь ai-agent

Отдельный пользователь для AI-агента с ограниченными правами. По умолчанию
агент ходит от `ai-agent` и работает в своём namespace. При необходимости
выполнить действия от имени `artlab` (bootstrap-скрипты, запись в проект)
агент запрашивает разрешение и использует `sudo -u artlab`.

### Развёртывание

```bash
# На сервере:
bash /home/artlab/projects/homelab/scripts/ai-agent-setup.sh
```

Скрипт создаёт пользователя, подключает симлинки dotfiles и ставит
sudoers-правило.

### Структура

```
dotfiles/ai-agent/
├── .zshrc              # Минимальный конфиг zsh (prompt с префиксом ai-agent)
├── .ssh/
│   └── authorized_keys # Restrictions: forwarding запрещён
└── sudoers.d-ai-agent  # NOPASSWD: sudo -u artlab -c "*"
```

### Модель доступа

| Действие | Как |
|---|---|
| Обычная работа (чтение, git, docker) | от `ai-agent` |
| Bootstrap-скрипты, запись в проект | `sudo -u artlab bash scripts/...` |
| Изменение прав/владельца файлов | Недоступно (нет root) |

### Генерация ключей

```bash
# На локальной машине:
ssh-keygen -t ed25519 -f ~/.ssh/ai-agent-key -C 'ai-agent@homelab'

# Добавить публичный ключ в dotfiles/ai-agent/.ssh/authorized_keys
# Скопировать на сервер:
scp dotfiles/ai-agent/.ssh/authorized_keys homelab:/home/ai-agent/.ssh/
```

## Приватные ключи artlab

Приватные ключи (`~/.ssh/id_lab_github` и т.п.) создаются на сервере один раз
и в репозиторий не попадают. Создание:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_lab_github

chmod 600 ~/.ssh/config
```
