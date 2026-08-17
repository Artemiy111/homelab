#!/usr/bin/env bash

# ai-agent-setup.sh — Создание пользователя ai-agent и настройка окружения.
# Запускать от имени artlab на сервере homelab.
# Скрипт идемпотентен: повторный запуск не ломает существующие настройки.

set -euo pipefail

AGENT_USER="ai-agent"
REPO_ROOT="/home/artlab/projects/homelab"
DOTFILES_SRC="$REPO_ROOT/dotfiles/ai-agent"
AGENT_HOME="/home/$AGENT_USER"

# --- 1. Создание пользователя ---
if id "$AGENT_USER" &>/dev/null; then
  echo "Пользователь $AGENT_USER уже существует."
else
  sudo useradd -m -s /bin/zsh "$AGENT_USER"
  echo "Пользователь $AGENT_USER создан."
fi

# --- 2. Симлинки dotfiles ---
sudo mkdir -p "$AGENT_HOME/.ssh"

for f in .zshrc; do
  if [ -f "$DOTFILES_SRC/$f" ]; then
    sudo ln -sf "$DOTFILES_SRC/$f" "$AGENT_HOME/$f"
    echo "Симлинк: ~$AGENT_USER/$f -> $DOTFILES_SRC/$f"
  fi
done

# SSH config и authorized_keys — вручную, не через симлинк (для .ssh безопаснее копировать)
if [ -f "$DOTFILES_SRC/.ssh/authorized_keys" ]; then
  sudo cp "$DOTFILES_SRC/.ssh/authorized_keys" "$AGENT_HOME/.ssh/authorized_keys"
  sudo chmod 600 "$AGENT_HOME/.ssh/authorized_keys"
  echo "authorized_keys скопирован (chmod 600)."
fi

# --- 4. Sudoers ---
SUDOERS_FILE="/etc/sudoers.d/ai-agent"
sudo install -m 440 "$DOTFILES_SRC/sudoers.d-ai-agent" "$SUDOERS_FILE"
sudo visudo -c
echo "Sudoers-правило установлено: $SUDOERS_FILE"

# --- 5. Права на домашний каталог ---
sudo chown -R "$AGENT_USER:$AGENT_USER" "$AGENT_HOME"
sudo chmod 700 "$AGENT_HOME"

echo ""
echo "Готово. Следующий шаг:"
echo "  1. Сгенерировать ключ на локальной машине:"
echo "     ssh-keygen -t ed25519 -f ~/.ssh/ai-agent-key -C 'ai-agent@homelab'"
echo "  2. Добавить публичный ключ в $DOTFILES_SRC/.ssh/authorized_keys"
echo "  3. Скопировать authorized_keys на сервер:"
echo "     scp $DOTFILES_SRC/.ssh/authorized_keys homelab:$AGENT_HOME/.ssh/"
echo "  4. Подключиться:"
echo "     ssh homelab -l ai-agent"
