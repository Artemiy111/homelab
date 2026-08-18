#!/usr/bin/env bash

# Создаёт первого (или дополнительного) администратора Synapse, не включая
# публичную регистрацию. Запускается на сервере под пользователем artlab.

set -euo pipefail

username="${1:-}"
if [[ -z "$username" ]]; then
  read -r -p 'Логин нового администратора: ' username
fi

if [[ ! "$username" =~ ^[a-z0-9._=-]+$ ]]; then
  echo 'Логин может содержать только строчные латинские буквы, цифры, ., _, = и -.' >&2
  exit 2
fi

exec docker exec -it element-synapse register_new_matrix_user \
  -c /data/homeserver.yaml \
  -u "$username" \
  -a \
  http://localhost:8008
