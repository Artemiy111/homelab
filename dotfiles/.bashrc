[[ $- != *i* ]] && [[ -z "$SSH_TTY" ]] && ! [[ "$SSH_ORIGINAL_COMMAND" =~ (^|/)scp|rsync ]] && ! [[ "$SSH_SUBSYSTEM" =~ sftp ]] && exit 0

# Алиасы и функции для интерактивных bash-сессий.
# Основной шелл пользователя — zsh (см. .zshrc); этот файл — fallback.
