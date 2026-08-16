#!/usr/bin/env bash
#
# Получить одноразовую ссылку для регистрации passkey (WebAuthn) у пользователя ZITADEL.
#
# Работает без SMTP: вызывает UserService.CreatePasskeyRegistrationLink с
# returnCode и сам собирает URL, который можно отправить пользователю любым
# каналом (Telegram, QR, лично).
#
# Требует PAT администратора (Console → Users → <admin> → Personal Access Tokens).
# PAT передаётся переменной окружения ZITADEL_PAT или спрашивается интерактивно.
#
# Пример:
#   ZITADEL_PAT=... ./scripts/zitadel-passkey-link.sh

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

info() { printf '\033[1;36m%s\033[0m\n' "$*" >&2; }
ok()   { printf '\033[1;32m%s\033[0m\n' "$*" >&2; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mОшибка: %s\033[0m\n' "$*" >&2; exit 1; }

# --- Хост ------------------------------------------------------------------
ZITADEL_HOST="${ZITADEL_HOST:-}"
if [[ -z "$ZITADEL_HOST" && -f "$repo_root/zitadel/.env" ]]; then
  ZITADEL_HOST="$(sed -n 's/^ZITADEL_HOST=//p' "$repo_root/zitadel/.env" | head -n1)"
fi
ZITADEL_HOST="${ZITADEL_HOST:-id.example.net}"

API_BASE="https://${ZITADEL_HOST}/v2"
LOGIN_BASE="https://${ZITADEL_HOST}/ui/v2/login"

# --- PAT -------------------------------------------------------------------
PAT="${ZITADEL_PAT:-}"
if [[ -z "$PAT" ]]; then
  read -rsp 'PAT (Console → Users → <admin> → Personal Access Tokens): ' PAT || true
  echo >&2
fi
[[ -n "$PAT" ]] || die 'PAT не задан (переменная ZITADEL_PAT или интерактивный ввод).'

# --- Helpers ---------------------------------------------------------------
api() {
  # api METHOD path [json_body]
  local method="$1" path="$2" body="${3:-}"
  local args=(-sS -X "$method" "$API_BASE$path" -H "Authorization: Bearer ${PAT}")
  if [[ -n "$body" ]]; then
    args+=(-H 'Content-Type: application/json' -d "$body")
  fi
  curl "${args[@]}"
}

error_message() {
  # Печатает текст ошибки ZITADEL (grpc-gateway) и возвращает 0, если это ошибка.
  local json="$1" msg
  msg="$(jq -r '.message // empty' <<<"$json")"
  if [[ -n "$msg" ]]; then
    printf '%s\n' "$msg"
    return 0
  fi
  return 1
}

# --- Выбор пользователя ----------------------------------------------------
info "ZITADEL: https://${ZITADEL_HOST}"

read -rp 'Логин или user ID (например user или 386564404046479363): ' target
[[ -n "$target" ]] || die 'пустой ввод.'

user_id=''
org_id=''
username=''
login=''

if [[ "$target" =~ ^[0-9]{5,}$ ]]; then
  # Похоже на user ID — берём пользователя напрямую.
  json="$(api GET "/users/${target}")"
  if msg="$(error_message "$json")"; then
    die "GetUserByID: $msg"
  fi
  user_id="$target"
  username="$(jq -r '.user.username // empty' <<<"$json")"
  login="$(jq -r '.user.preferredLoginName // empty' <<<"$json")"
  org_id="$(jq -r '.user.details.resourceOwner // empty' <<<"$json")"
else
  # Ищем по логину (без учёта регистра, по подстроке).
  body="$(jq -nc --arg q "$target" \
    '{queries:[{loginNameQuery:{loginName:$q,method:"TEXT_QUERY_METHOD_CONTAINS_IGNORE_CASE"}}]}')"
  json="$(api POST '/users' "$body")"
  if msg="$(error_message "$json")"; then
    die "ListUsers: $msg"
  fi

  mapfile -t users < <(jq -r \
    '.result[]? | [.userId, (.username // ""), (.preferredLoginName // ""), (.details.resourceOwner // "")] | @tsv' \
    <<<"$json")

  if [[ ${#users[@]} -eq 0 ]]; then
    die "пользователь по \"$target\" не найден."
  fi

  if [[ ${#users[@]} -eq 1 ]]; then
    IFS=$'\t' read -r user_id username login org_id <<<"${users[0]}"
  else
    info 'Найдено несколько пользователей:'
    local i=1 line uid uname ulogin
    for line in "${users[@]}"; do
      IFS=$'\t' read -r uid uname ulogin _ <<<"$line"
      printf '  %d) %s (%s)  id=%s\n' "$i" "$uname" "$ulogin" "$uid" >&2
      i=$((i + 1))
    done
    read -rp 'Номер: ' choice
    [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#users[@]})) \
      || die 'неверный номер.'
    IFS=$'\t' read -r user_id username login org_id <<<"${users[$((choice - 1))]}"
  fi
fi

[[ -n "$user_id" && -n "$org_id" ]] || die 'не удалось определить user ID / organization ID.'

info "Пользователь: ${username:-<без username>} (${login:-<без логина>})"
info "user_id=$user_id  organization=$org_id"

# --- Код и ссылка ----------------------------------------------------------
json="$(api POST "/users/${user_id}/passkeys/registration_link" '{"returnCode":{}}')"
if msg="$(error_message "$json")"; then
  die "CreatePasskeyRegistrationLink: $msg"
fi

code_id="$(jq -r '.code.id // empty' <<<"$json")"
code="$(jq -r '.code.code // empty' <<<"$json")"
[[ -n "$code_id" && -n "$code" ]] || die 'в ответе API нет кода.'

url="${LOGIN_BASE}/passkey/set?codeId=${code_id}&code=${code}&userId=${user_id}&organization=${org_id}"

ok 'Ссылка для регистрации passkey:'
printf '\033[1m%s\033[0m\n' "$url"
echo

warn 'Код одноразовый: ссылку надо открыть на том устройстве, где будет храниться passkey, и пройти регистрацию до конца с первого раза (ZITADEL #12499).'
