#!/usr/bin/env bash

# Пост-старт конфигурация Seafile. Запускается ПОСЛЕ `docker compose up -d`,
# когда контейнер seafile уже работает: подключает примонтированные файлы
# настроек (OnlyOffice, OAuth2 через Zitadel) в seahub_settings.py, патчит
# создание пользователей (чтобы SSO линковал аккаунты по email), мигрирует
# уже существующих пользователей с virtual-id и перезапускает воркер Seahub.
#
# Требует запущенного контейнера; при вызове до `up -d` завершается с ошибкой.

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

service="seafile"
container="seafile"

# DOMAIN нужен для удаления bootstrap-admin (admin@$DOMAIN). Берём из корневого
# config.env, т.к. compose интерполирует INIT_SEAFILE_ADMIN_EMAIL: admin@${DOMAIN},
# а service_run инжектит только секреты (не compose-env).
if [[ -f "$repo_root/config.env" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$repo_root/config.env"
  set +a
fi

if ! docker inspect --format '{{.State.Running}}' "$container" 2>/dev/null | grep -qx true; then
  echo "Ошибка: контейнер $container не запущен. Сначала поднимите стек:" >&2
  echo "  cd $repo_root/apps/seafile && docker compose up -d" >&2
  exit 1
fi

# Подключаем seahub_onlyoffice.py (примонтирован в compose.yaml) к настройкам
# Seahub. Файл настроек создаёт контейнер от root, поэтому дописываем через
# docker exec. Идемпотентно: при повторных запусках строка уже есть.
docker exec "$container" sh -c '
  test -f "$1" || exit 0
  grep -q "BEGIN HOMELAB ONLYOFFICE" "$1" && exit 0
  printf "\n# BEGIN HOMELAB ONLYOFFICE\nexec(open(\"/shared/seafile/conf/seahub_onlyoffice.py\").read())\n# END HOMELAB ONLYOFFICE\n" >>"$1"
  echo "Подключён seahub_onlyoffice.py"
' sh /shared/seafile/conf/seahub_settings.py

# Подключаем seahub_oauth.py (OAuth2 через Zitadel) к настройкам Seahub.
docker exec "$container" sh -c '
  test -f "$1" || exit 0
  grep -q "BEGIN HOMELAB OAUTH" "$1" && exit 0
  printf "\n# BEGIN HOMELAB OAUTH\nexec(open(\"/shared/seafile/conf/seahub_oauth.py\").read())\n# END HOMELAB OAUTH\n" >>"$1"
  echo "Подключён seahub_oauth.py"
' sh /shared/seafile/conf/seahub_settings.py

# ---------------------------------------------------------------------------
# Патчи Seafile (версионно-зависимы от seafileltd/seafile-mc:13.0.25).
#
# Патч-файлы лежат рядом со скриптом: apps/seafile/patches/. Генерируются diff-ом
# ванильного кода образа и пропатченного (инструкция — в README.md). Применяем
# `patch -N -p1` из каталога seahub внутри контейнера:
#   - seahub-base-accounts.patch: create_user пишет реальный email как
#     канонический логин (вместо virtual-id <hex>@auth.local), чтобы generic
#     OAuth линковал аккаунты по email.
#   - seahub-oauth-views.patch: JIT-провижининг неизвестного юзера при первом
#     SSO и назначение админом только аккаунта INIT_SEAFILE_ADMIN_EMAIL.
# `patch -N` идемпотентен: уже применённый патч — no-op (пропуск), а расхождение
# контекста (апгрейд Seafile) — громкая ошибка, а не тихий баг. Переприменяется
# при каждом деплое / --force-recreate.
# ---------------------------------------------------------------------------
PATCH_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/patches"
SEA_HOME="/opt/seafile/seafile-server-latest/seahub"

apply_patch() {
  local name="$1"
  local ptmp="/tmp/${name}.patch"
  docker cp "$PATCH_DIR/$name.patch" "$container:$ptmp"
  # Сухая проверка БЕЗ -N. По ТЕКСТУ вывода различаем три состояния:
  #   - "previously applied"/"Skipping patch" -> уже применён, no-op;
  #   - "FAILED"/"mismatch"/"Reversed"        -> контекст не совпал (новая
  #                                              версия Seafile), ошибка;
  #   - иначе                                  -> чистое применение через patch -N.
  # Важно: без -N сухая проверка возвращает 0 ДАЖЕ для уже применённого патча
  # (пишет "Skipping patch"), поэтому ориентируемся на текст, а не на код.
  local out
  # patch --dry-run возвращает не-ноль для уже применённого/пропущенного патча,
  # поэтому подавляем статус, чтобы set -e не прервал скрипт (текст разбираем ниже).
  out="$(docker exec "$container" patch --dry-run -p1 -d "$SEA_HOME" -i "$ptmp" 2>&1)" || true
  if echo "$out" | grep -q "previously applied\|Skipping patch"; then
    echo "Патч уже применён (пропуск): $name"
  elif echo "$out" | grep -q "FAILED\|mismatch\|Reversed"; then
    echo "ОШИБКА: контекст патча не совпал (возможно, новая версия Seafile): $name" >&2
    docker exec "$container" rm -f "$ptmp"
    exit 1
  elif docker exec "$container" patch -N -p1 -d "$SEA_HOME" -i "$ptmp" >/dev/null 2>&1; then
    echo "Применён патч: $name"
  else
    echo "ОШИБКА: не удалось применить патч: $name" >&2
    docker exec "$container" rm -f "$ptmp"
    exit 1
  fi
  docker exec "$container" rm -f "$ptmp"
}

apply_patch seahub-base-accounts
apply_patch seahub-oauth-views

# ---------------------------------------------------------------------------
# Миграция уже существующих пользователей с virtual-id (<hex>@auth.local):
# выставляем EmailUser.email = Profile.contact_email и синхронизируем Profile.user.
# Идемпотентно: трогает только @auth.local; после миграции повторные запуски — no-op.
# Пароль рута БД берём из окружения контейнера (через service_run), без секретов в репо.
# ---------------------------------------------------------------------------
ROOT_PW="$(service_run seafile bash -c 'echo "$INIT_SEAFILE_MYSQL_ROOT_PASSWORD"')" || true
if [ -n "${ROOT_PW:-}" ]; then
  docker exec seafile-db mysql -uroot -p"$ROOT_PW" -N -e "
    UPDATE ccnet_db.EmailUser AS e
    INNER JOIN seahub_db.profile_profile AS p ON p.user = e.email
    SET e.email = p.contact_email
    WHERE e.email LIKE '%@auth.local' AND p.contact_email IS NOT NULL AND p.contact_email <> '';
    UPDATE seahub_db.profile_profile AS p
    SET p.user = p.contact_email
    WHERE p.user LIKE '%@auth.local' AND p.contact_email IS NOT NULL AND p.contact_email <> '';
    SELECT 'migrated @auth.local users:' AS msg, COUNT(*) FROM ccnet_db.EmailUser WHERE email LIKE '%@auth.local';
  " && echo "Миграция virtual-id пользователей выполнена" || echo "Миграция пропущена (ошибка SQL)"
else
  echo "Миграция пропущена: не удалось получить пароль рута БД"
fi

# ---------------------------------------------------------------------------
# Удаляем bootstrap-admin (admin@$DOMAIN), чтобы первый зашедший через Zitadel
# пользователь стал админом Seafile (см. OAUTH_PROMOTE_FIRST_USER_TO_ADMIN).
# Idempotent: удаляет, только если аккаунт ещё существует.
# ---------------------------------------------------------------------------
ADMIN_EMAIL="admin@${DOMAIN:?DOMAIN не задан в config.env}"
# На свежей БД entrypoint Seafile создаёт bootstrap-admin асинхронно ПОСЛЕ старта
# контейнера. Ждём его появления, иначе удаление (ниже) пройдёт мимо и аккаунт
# останется. Ждём до ~120с, затем удаляем в любом случае (idempotent).
if [ -n "${ROOT_PW:-}" ]; then
  for i in $(seq 1 60); do
    cnt="$(docker exec seafile-db mysql -uroot -p"$ROOT_PW" -N -e "SELECT COUNT(*) FROM ccnet_db.EmailUser WHERE email='$ADMIN_EMAIL';" 2>/dev/null)"
    # Выходим, как только получили определённый ответ: 1 — аккаунт есть (ждали),
    # 0 — уже удалён (ждать нечего). Ждём только пока БД недоступна (cnt пуст).
    [ "${cnt:-x}" = "1" ] || [ "${cnt:-x}" = "0" ] && break
    sleep 2
  done
fi
# Удаляем аккаунт bootstrap-admin по всем таблицам. Ключевая колонка различается
# (username/user/email) — указываем её явно для каждой таблицы. Таблицы, которых
# нет в этой версии Seafile (api2_token_v2), пропускаем (2>/dev/null || true).
del_admin() {
  docker exec seafile-db mysql -uroot -p"$ROOT_PW" -N -e "DELETE FROM $1 WHERE $2='$ADMIN_EMAIL';" 2>/dev/null || true
}
if [ -n "${ROOT_PW:-}" ]; then
  # Не удаляем, если admin@ уже привязан к SSO (создан через JIT) — это реальный
  # админ, а не bootstrap-заглушка. Иначе повторный запуск снёс бы рабочего админа.
  linked="$(docker exec seafile-db mysql -uroot -p"$ROOT_PW" -N -e "SELECT COUNT(*) FROM seahub_db.social_auth_usersocialauth WHERE username='$ADMIN_EMAIL';" 2>/dev/null || echo 0)"
  if [ "${linked:-0}" != "0" ]; then
    echo "Bootstrap-admin $ADMIN_EMAIL уже привязан к SSO — не удаляем (это реальный админ)."
  else
    del_admin seahub_db.social_auth_usersocialauth username
    del_admin seahub_db.api2_token user
    del_admin seahub_db.profile_profile user
    del_admin ccnet_db.EmailUser email
    remaining="$(docker exec seafile-db mysql -uroot -p"$ROOT_PW" -N -e "SELECT COUNT(*) FROM ccnet_db.EmailUser WHERE email='$ADMIN_EMAIL';" 2>/dev/null || echo '?')"
    echo "Bootstrap-admin $ADMIN_EMAIL: remaining EmailUser=$remaining (JIT: первый Zitadel-вход = админ)"
  fi
else
  echo "Bootstrap-admin не удалён: пароль рута БД недоступен"
fi

echo "Применяем настройки Seahub (перезапуск контейнера)..."
docker restart "$container"

echo "Готово: OnlyOffice, OAuth2 подключены, создание/SSO пользователей совместимо."
