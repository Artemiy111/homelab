# Seafile (homelab)

Seafile CE в Kubernetes k0s с SSO через Zitadel и OnlyOffice.

Источник истины — манифесты в `apps/seafile/k8s/`. Скрипт
`apps/seafile/prepare-seahub.sh`, конфиги `seahub_oauth.py` /
`seahub_onlyoffice.py` и каталог `patches/` используются подом в кластере.

## Архитектура

```
Zitadel (id.example.com)
   │  OIDC / generic OAuth2 (authorization code)
   ▼
Seafile (seafile.example.com)          ── seahub_oauth.py
   │  файлы                                  ── seahub_onlyoffice.py
   ▼
OnlyOffice (seafile/k8s/onlyoffice.*)

MariaDB seafile-mariadb  ←  mariadb-operator
```

- **Zitadel** — IdP. Приложение типа «generic OAuth» (не Seafile-специфичное),
  потому что Seafile CE умеет только generic OAuth2, а не OIDC-дискавери.
- **Seafile** — `seafileltd/seafile-mc:13.0.25`, Deployment `seafile`.
- **OnlyOffice** — отдельный Deployment в этом же namespace; подключается через
  примонтированный `seahub_onlyoffice.py`.
- **Redis** — `valkey/valkey:9-alpine`, Deployment `seafile-redis`.
- **БД** — MariaDB-инстанс `seafile-mariadb` под mariadb-operator.

Конфиги `seahub_oauth.py` и `seahub_onlyoffice.py` примонтированы read-only из
репо (hostPath) и подключаются в `seahub_settings.py` по маркерам
`BEGIN HOMELAB OAUTH` / `BEGIN HOMELAB ONLYOFFICE`.

## База данных (mariadb-operator)

Инстанс и SQL-ресурсы объявлены в `platform/mariadb/`:

| Ресурс | Что создаёт |
|--------|-------------|
| `MariaDB seafile-mariadb` | сам инстанс, Service `seafile-mariadb:3306` |
| `Database ccnet-db / seafile-db / seahub-db` | `ccnet_db`, `seafile_db`, `seahub_db` |
| `User seafile` + 3 `Grant` | пользователь `seafile` с `ALL PRIVILEGES` на три БД |

- Приложение ходит по env `SEAFILE_MYSQL_DB_HOST=seafile-mariadb` под
  пользователем `seafile`, который имеет `ALL PRIVILEGES` **только на три БД**.
- root знает только оператор (через `rootPasswordSecretKeyRef` на
  `seafile/INIT_SEAFILE_MYSQL_ROOT_PASSWORD`). Приложению root на рантайме не
  нужен: Seafile пропускает bootstrap, если `/shared/seafile` уже инициализирован
  (в логах `Skip running setup-seafile-mysql.py because there is existing
  seafile-data folder`).
- Storage — Longhorn `longhorn-retain`, 512Mi.

Раньше БД была обычным Deployment `seafile-db` на hostPath
`/storage/apps/seafile/mysql`. Мигрировано на оператор (logical dump → restore),
старый Deployment/Service и каталог удалены.

### Бэкап и восстановление

Дамп (на сервере):

```sh
kubectl -n seafile exec -i seafile-mariadb-0 -- sh -c \
  'mariadb-dump -uroot -p"$MARIADB_ROOT_PASSWORD" --single-transaction \
   --routines --events --triggers --databases ccnet_db seafile_db seahub_db' \
  > /storage/apps/seafile/backups/seafile-$(date +%F).sql
```

Восстановление в уже существующие БД (root-пароль доступен в поде через env):

```sh
kubectl -n seafile exec -i seafile-mariadb-0 -- sh -c \
  'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD"' < <dump>.sql
```

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

### Применение в k8s

Патчи накладываются при старте пода. Контейнер `seafile` обёрнут в
`apps/seafile/prepare-seahub.sh` (override `command` в
`apps/seafile/k8s/seafile.deployment.yaml`); скрипт до запуска seahub:

1. подключает `seahub_oauth.py` / `seahub_onlyoffice.py` в `seahub_settings.py`
   (идемпотентно, по маркерам);
2. накладывает патчи из примонтированного каталога `patches/` (идемпотентно:
   уже применённый патч пропускается, расхождение контекста — громкая ошибка,
   и под не стартует).

Init-контейнером это не сделать: код seahub лежит в слое образа, а не на общем
томе, поэтому подменяется `command` основного контейнера. Патч promotion читает
`INIT_SEAFILE_ADMIN_EMAIL` из env — переменная обязана оставаться в манифесте.

### Патч-файлы (`apps/seafile/patches/`)

Патчи — это настоящие unified diff, сгенерированные из ванильного кода образа и
пропатченного. Версия Seafile: **13.0.25**.

| Файл | Меняет |
|------|--------|
| `seahub-base-accounts.patch` | `UserManager.create_user` → реальный email как логин |
| `seahub-oauth-views.patch` | `oauth_callback`: JIT + `_any_staff_user` (через `User.objects.get_superusers()`) + admin-email promotion |

`patch -N` делает применение идемпотентным: уже применённый патч — no-op
(«previously applied», пропуск), а расхождение контекста (новая версия Seafile) —
громкая ошибка, а не «тихое» применение не туда. Пути в патче относительны
`seafile-server-latest/seahub`; применяем с `-p1` из этого каталога.

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
- **Симлинк `seafile-server-latest`** создаётся entrypoint только в рантайме
  контейнера; в свежем образе его нет — берём версионированный путь.
- **k8s env-конфиг не персистится в `conf/`.** Хост БД Seafile 13 читает из env
  (`seahub/settings.py`, `seafevents`), а не из `seafile.conf`/`seahub_settings.py`.
  Смена `SEAFILE_MYSQL_DB_HOST` + рестарт пода достаточна для переключения БД.
- **NetworkPolicy `seafile` — default-deny.** Оператор ходит в БД из namespace
  `mariadb-system`; ему нужен явный ingress на 3306 (см. `apps/seafile/k8s/networkpolicy.yaml`),
  иначе SQL-ресурсы не сходятся с `i/o timeout`.
- **`kubectl exec -i` в `bash -s`-скрипте съедает остаток stdin.** Если гоняешь
  многошаговый скрипт через `ssh ... bash -s`, не используй `-i` без явного
  `< /dev/null`/`< file`, иначе следующие строки скрипта уйдут в stdin команды.
