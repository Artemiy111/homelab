# Seafile (homelab)

Seafile CE в Kubernetes k0s с SSO через Zitadel и OnlyOffice. Этот каталог —
всё, что касается Seafile: compose-стек, конфиги и **пост-старт патчи**, без
которых SSO не работает «из коробки».

## Архитектура

```
Zitadel (id.example.com)
   │  OIDC / generic OAuth2 (authorization code)
   ▼
Seafile (seafile.example.com)  ── seahub_oauth.py
   │  файлы
   ▼
OnlyOffice (в том же стеке)         ── seahub_onlyoffice.py
```

- **Zitadel** — IdP. Приложение типа «generic OAuth» (не Seafile-специфичное),
  потому что Seafile CE умеет только generic OAuth2, а не OIDC-дискавери.
- **Seafile** — `seafileltd/seafile-mc` (community edition, single-container,
  включает seafile + seahub + mysql + OnlyOffice-connector).
- **OnlyOffice** — отдельный контейнер в этом же compose-стеке; подключается
  через примонтированный `seahub_onlyoffice.py`.

Конфиги (`seahub_oauth.py`, `seahub_onlyoffice.py`) примонтированы в контейнер
read-only из репо и дописываются в `seahub_settings.py` при пост-старте
(маркеры `BEGIN HOMELAB OAUTH` / `BEGIN HOMELAB ONLYOFFICE`).

## Почему нужны патчи

Seafile CE делает две вещи, ломающие нормальный SSO, и одну, которой не хватает:

1. **virtual-id вместо email.** `UserManager.create_user` (seahub/base/accounts.py)
   создаёт пользователя с каноническим логином вида `<hex>@auth.local`
   (`gen_user_virtual_id()`), а настоящий адрес кладёт в `Profile.contact_email`.
   Generic OAuth ищет аккаунт **только** по `EmailUser.email`
   (`get_old_user` / `RemoteUserBackend.authenticate`), поэтому SSO не находил
   аккаунт и выдавал «new user registration is not allowed». Bootstrap-admin
   работает, потому что пишет реальный email напрямую — именно под него и
   затачиваем патч.
   **Патч:** `create_user` использует реальный email как канонический логин
   (как bootstrap).

2. **Нет JIT-провижининга.** Даже при `OAUTH_CREATE_UNKNOWN_USER = True` Seafile
   CE не создаёт неизвестного юзера — падает в ту же ошибку.
   **Патч:** в `except User.DoesNotExist` ветки `oauth_callback` добавляем
   авто-создание через `User.objects.create_user`.

3. **Нет назначения админа при SSO.** Нужно, чтобы первый/нужный цитадель-юзер
   стал админом Seafile (вместо удаляемого bootstrap-admin).
   **Патч:** при JIT новый юзер становится `is_staff=True` **только** если его
   email совпадает с `INIT_SEAFILE_ADMIN_EMAIL` (`admin@<DOMAIN>`). Это
   детерминированно: `user@` и любой другой никогда не станут админом,
   независимо от порядка входа.

## Патч-файлы (`apps/seafile/patches/`)

Патчи — это настоящие unified diff, сгенерированные из ванильного кода образа и
пропатченного. Версия Seafile на момент написания: **13.0.25**.

| Файл | Меняет |
|------|--------|
| `seahub-base-accounts.patch` | `UserManager.create_user` → реальный email как логин |
| `seahub-oauth-views.patch` | `oauth_callback`: JIT + `_any_staff_user` (через `User.objects.get_superusers()`) + admin-email promotion |

Применяются в `init-postinstall.sh` через:

```bash
docker cp apps/seafile/patches/<name>.patch seafile:/tmp/<name>.patch
docker exec seafile patch -N -p1 -d /opt/seafile/seafile-server-latest/seahub -i /tmp/<name>.patch
```

`patch -N` делает применение **идемпотентным**: уже применённый патч — no-op
(сообщение «previously applied», пропуск), а расхождение контекста (новая версия
Seafile) — громкая ошибка, а не «тихое» применение не туда.

Пути в патче относительны `seahub-server-latest/seahub`; применяем с `-p1`
именно из этого каталога.

## Как пересобрать патч при апгрейде Seafile

Патч версионно-зависим (как и было). При смене тега образа:

```bash
IMG=seafileltd/seafile-mc:<new-version>
VER=/opt/seafile/seafile-server-<new-version>/seahub   # в образе НЕТ симлинка latest
LATEST=/opt/seafile/seafile-server-latest/seahub        # только в рантайме контейнера

# ванильные файлы — прямо из образа (симлинк latest создаётся entrypoint, не берём его)
docker run --rm --entrypoint cat "$IMG" "$VER/seahub/oauth/views.py"   > /tmp/vanilla_views.py
docker run --rm --entrypoint cat "$IMG" "$VER/seahub/base/accounts.py" > /tmp/vanilla_accounts.py

# целевые (пропатченные) — из работающего контейнера
docker exec seafile cat "$LATEST/seahub/oauth/views.py"   > /tmp/patched_views.py
docker exec seafile cat "$LATEST/seahub/base/accounts.py" > /tmp/patched_accounts.py

diff -u --label a/seahub/oauth/views.py  --label b/seahub/oauth/views.py  /tmp/vanilla_views.py  /tmp/patched_views.py  > apps/seafile/patches/seahub-oauth-views.patch
diff -u --label a/seahub/base/accounts.py --label b/seahub/base/accounts.py /tmp/vanilla_accounts.py /tmp/patched_accounts.py > apps/seafile/patches/seahub-base-accounts.patch
```

Если контекст ушёл — `patch` упадёт при пост-старте, и патч надо обновить
вручную (подправить hunks под новый код).

## Пост-старт (`init-postinstall.sh`)

Запускается ПОСЛЕ `docker compose up -d` (контейнер уже работает). Порядок:

1. Дописывает `seahub_onlyoffice.py` и `seahub_oauth.py` в `seahub_settings.py`
   (идемпотентно по маркерам).
2. Применяет оба патча (`apply_patch`, см. выше).
3. Мигрирует старых юзеров с `@auth.local`:
   `EmailUser.email = Profile.contact_email`, синхронизирует `profile_profile.user`.
   Трогает только `@auth.local`, повторные запуски — no-op.
4. Удаляет bootstrap-admin (`admin@<DOMAIN>`) по всем таблицам, чтобы первый
   Zitadel-вход под этим email стал админом. Entrypoint Seafile создаёт
   bootstrap-admin **асинхронно после старта**, поэтому перед удалением скрипт
   ждёт появления аккаунта (цикл ~120с), иначе удаление прошло бы мимо.
5. `docker restart seafile` — подхватить патчи и настройки.

Запуск (на сервере, от `artlab`, через обёртку compose):

```bash
bash scripts/compose.sh seafile run --rm init-postinstall   # или service_run
```

## Грабли (пойманные баги)

- **`User.objects` — это кастомный `UserManager`, а не Django Manager.** У него
  НЕТ `.filter()` / `.exists()`. Запрос `User.objects.filter(is_staff=True).exists()`
  падал с `AttributeError`, который глушился `try/except` в проверке админа →
  функция всегда возвращала `False` → **каждый** JIT-юзер становился админом.
  Правильный метод: `User.objects.get_superusers()` (через `ccnet_threaded_rpc`).
- **`ccnet_api` — это класс, а не инстанс.** Для RPC используй
  `ccnet_threaded_rpc`.
- **Тихий `except`** в патчах чужого кода маскирует реальные ошибки — проверяй,
  что вызываемый метод реально существует в рантайме.
- **`docker exec python - <<'HEREDOC'` без `-i`** молча скипает stdin → патч не
  применяется, без ошибки. Теперь используем файлы патчей, эта ловушка устранена.
- **Симлинк `seafile-server-latest`** создаётся entrypoint только в рантайме
  контейнера; в свежем образе его нет — берём версионированный путь.
- **`docker compose` schema validation** падает с `stat .: permission denied`,
  если cwd недоступен пользователю `artlab`. Запускай через
  `cd /home/artlab/projects/homelab && bash scripts/compose.sh seafile ...`.

## Воспроизводимость

Стек хранит данные в bind-мount (`/storage/apps/seafile/mysql`, `.../shared`),
не в named volumes. `docker compose up -d --force-recreate` пересоздаёт
контейнер из образа (сбрасывая патчи в коде) — `init-postinstall.sh` заново
применяет патчи, миграцию и удаляет bootstrap-admin. Полный сброс БД:

```bash
docker compose down
sudo -u artlab docker run --rm -v /storage/apps/seafile:/data alpine rm -rf /data/mysql /data/shared
docker compose up -d && bash scripts/compose.sh seafile run --rm init-postinstall
```
