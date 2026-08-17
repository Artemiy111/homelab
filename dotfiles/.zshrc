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

# --- История ---
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS

# --- Удобное поведение ---
setopt AUTO_CD
setopt INTERACTIVE_COMMENTS
setopt NO_BEEP
setopt EXTENDED_GLOB

# --- Автодополнение ---
autoload -Uz compinit
compinit
zstyle ':completion:*' menu select

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
