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
#   ZITADEL_PAT=... ./zitadel/zitadel-passkey-link.sh

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$repo_root/scripts/lib/common.sh"

info() { printf '\033[1;36m%s\033[0m\n' "$*" >&2; }
ok()   { printf '\033[1;32m%s\033[0m\n' "$*" >&2; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mОшибка: %s\033[0m\n' "$*" >&2; exit 1; }

# --- Хост ------------------------------------------------------------------
ZITADEL_HOST="${ZITADEL_HOST:-}"
if [[ -z "$ZITADEL_HOST" && -f "$script_dir/.env" ]]; then
  ZITADEL_HOST="$(sed -n 's/^ZITADEL_HOST=//p' "$script_dir/.env" | head -n1)"
fi
ZITADEL_HOST="${ZITADEL_HOST:-id.$DOMAIN}"

API_BASE="https://${ZITADEL_HOST}/v2"
LOGIN_BASE="https://${ZITADEL_HOST}/ui/v2/login"

# --- PAT -------------------------------------------------------------------
PAT="${ZITADEL_PAT:-}"
if [[ -z "$PAT" ]]; then
  read -rsp 'PAT (Console → Users → <admin> → Personal Access Tokens): ' PAT || true
  echo >&2
fi
[[ -n "$PAT" ]] || die 'PAT не задан (переменная ZITADEL_PAT или интерактивный ввод).'

# --- API: умирает сама, если в ответе есть .message -------------------------
api() {
  # api METHOD path [json_body]
  local method="$1" path="$2" body="${3:-}" resp msg
  local args=(-sS -X "$method" "$API_BASE$path" -H "Authorization: Bearer ${PAT}")
  [[ -n "$body" ]] && args+=(-H 'Content-Type: application/json' -d "$body")
  resp="$(curl "${args[@]}")"
  msg="$(jq -r '.message // empty' <<<"$resp")"
  [[ -z "$msg" ]] || die "$msg"
  printf '%s' "$resp"
}

# --- Поиск пользователя ----------------------------------------------------
info "ZITADEL: https://${ZITADEL_HOST}"

read -rp 'Логин или user ID (например user или 386564404046479363): ' target
[[ -n "$target" ]] || die 'пустой ввод.'

# Один вызов ListUsers на оба случая: число — точный поиск по ID,
# иначе — подстрока логина без учёта регистра.
if [[ "$target" =~ ^[0-9]{5,}$ ]]; then
  body="$(jq -nc --arg id "$target" '{queries:[{inUserIdsQuery:{userIds:[$id]}}]}')"
else
  body="$(jq -nc --arg q "$target" \
    '{queries:[{loginNameQuery:{loginName:$q,method:"TEXT_QUERY_METHOD_CONTAINS_IGNORE_CASE"}}]}')"
fi
json="$(api POST '/users' "$body")"

mapfile -t users < <(jq -r \
  '.result[]? | [.userId, (.username // ""), (.preferredLoginName // ""), (.details.resourceOwner // "")] | @tsv' \
  <<<"$json")

[[ ${#users[@]} -gt 0 ]] || die "пользователь по \"$target\" не найден."

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

[[ -n "$user_id" && -n "$org_id" ]] || die 'не удалось определить user ID / organization ID.'

info "Пользователь: ${username:-<без username>} (${login:-<без логина>})"
info "user_id=$user_id  organization=$org_id"

# --- Код и ссылка ----------------------------------------------------------
json="$(api POST "/users/${user_id}/passkeys/registration_link" '{"returnCode":{}}')"

code_id="$(jq -r '.code.id // empty' <<<"$json")"
code="$(jq -r '.code.code // empty' <<<"$json")"
[[ -n "$code_id" && -n "$code" ]] || die 'в ответе API нет кода.'

url="${LOGIN_BASE}/passkey/set?codeId=${code_id}&code=${code}&userId=${user_id}&organization=${org_id}"

ok 'Ссылка для регистрации passkey:'
printf '\033[1m%s\033[0m\n' "$url"
echo

warn 'Код одноразовый: ссылку надо открыть на том устройстве, где будет храниться passkey, и пройти регистрацию до конца с первого раза (ZITADEL #12499).'
