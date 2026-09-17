# ============================================================
#  zsh — минимальный конфиг для homelab (artlab)
#  ~/.zshrc читается каждой интерактивной сессией zsh
# ============================================================

# --- PATH (сохраняем то, что было настроено в fish/bash) ---
export PATH="$HOME/.local/bin:$PATH"     # пользовательские утилиты (lazydocker)
export BUN_INSTALL="$HOME/.bun"          # bun
export PATH="$BUN_INSTALL/bin:$PATH"

# --- Редактор по умолчанию ---
export EDITOR=nvim
export VISUAL=nvim
# zsh выбирает keymap по $EDITOR: "nvim" содержит подстроку "vi" и молча
# включает vi-режим (после случайного ESC буквы становятся vi-командами).
bindkey -e

# --- История ---
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS

# --- Удобное поведение ---
setopt INTERACTIVE_COMMENTS
setopt NO_BEEP
setopt EXTENDED_GLOB

# --- Автодополнение ---
autoload -Uz compinit
compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# Fish-like autosuggestions (нужен плагин zsh-autosuggestions)
# git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
if [[ -f "$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh"
  ZSH_AUTOSUGGEST_STRATEGY=(history completion)
  ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#666"
  bindkey '^ ' autosuggest-accept   # Ctrl+Space — принять подсказку
fi

# --- Git-ветка в подсказке ---
autoload -Uz vcs_info
zstyle ':vcs_info:*' formats '(%F{magenta}%b%f) '
precmd() { vcs_info }
setopt PROMPT_SUBST   # без этой опции ${vcs_info_msg_0_} выводится как текст
PROMPT='%F{green}%n@%m%f %F{blue}%~%f ${vcs_info_msg_0_}> '

# --- Поиск по истории стрелками вверх/вниз ---
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward

# --- Алиасы ---
alias ls='ls --color=auto'
alias ll='ls -lah'
alias la='ls -A'
alias l='ls -F'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias g='git'
alias gs='git status'
alias gp='git pull --ff-only'
alias gc='git clone'

# bun completions
[ -s "/home/artlab/.bun/_bun" ] && source "/home/artlab/.bun/_bun"

# kubectl (через k0s; автодополнение kubectl невозможно — k0s-сборка
# не имеет внутренней команды __complete, нужной zsh-скрипту completion)
export KUBECONFIG=/home/artlab/.kube/config
alias kubectl='k0s kubectl'
alias k='kubectl'

# k0s completion
if command -v k0s >/dev/null 2>&1; then
  source <(k0s completion zsh)
fi

# kubectl-cnpg completion
if command -v kubectl-cnpg >/dev/null 2>&1; then
  source <(kubectl-cnpg completion zsh)
fi

# `k cnpg ...` (алиасы k/kubectl → `k0s kubectl`) отдаём дополнению плагина:
# zsh разворачивает алиасы в словах, поэтому строку перехватывает функция k0s,
# а скрипт плагина не вызывается — он всегда зовёт `${words[1]} __complete`,
# то есть в words[1] обязан быть сам бинарь. Остальное (kubectl, k0s) уходит
# в k0s как раньше.
_kubectl_cnpg_proxy() {
  local off=0
  if [[ $words[2] == kubectl && $words[3] == cnpg ]]; then
    off=4
  elif [[ $words[2] == cnpg ]]; then
    off=3
  fi
  if (( ! off )); then
    (( $+functions[_k0s] )) && _k0s
    return
  fi
  words=(kubectl-cnpg "${words[off,-1]}")
  (( CURRENT = CURRENT - off + 2 ))
  (( CURRENT < 2 )) && CURRENT=2
  (( CURRENT > $#words )) && words+=("")
  _kubectl-cnpg
}
compdef _kubectl_cnpg_proxy k0s k kubectl
