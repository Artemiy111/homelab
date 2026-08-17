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

## Приватные ключи

Приватные ключи (`~/.ssh/id_lab_github` и т.п.) создаются на сервере один раз
и в репозиторий не попадают. Создание:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_lab_github

chmod 600 ~/.ssh/config
```
