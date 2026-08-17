# Zitadel

Zitadel — основной IdP homelab (Authentik оставлен для сравнения). Один Go-бинар (API + консоль),
PostgreSQL и отдельный контейнер Login V2 (Next.js). Доступен через Traefik по
`https://id.example.net/`; консоль — `/ui/console`, вход — `/ui/v2/login`.
Порты контейнеров на хосте не публикуются.

## Состав

- `postgres` — PostgreSQL, данные в `$APPS_STORAGE_PATH/zitadel/postgresql`.
- `zitadel` — API + консоль (gRPC/REST на 8080); пишет bootstrap-PAT для Login V2.
- `login` — Login V2 (`/ui/v2/login`, порт 3000); читает тот же bootstrap-том.
- `backup-db` (profile `tools`) — согласованный `pg_dump` перед Restic.

Роутинг повторяет официальный compose upstream: `/` → Login V2, `/ui/v2/login`
→ Login V2, `/api` → API (с strip-prefix), всё остальное → консоль. TLS
терминирует общий Traefik (`websecure`), поэтому `ZITADEL_TLS_ENABLED=false`,
`ZITADEL_EXTERNALSECURE=true`.

## Первый запуск

`scripts/bootstrap-platform.sh` создаёт `zitadel/.env` со случайными
`POSTGRES_PASSWORD`, `ADMIN_PASSWORD` и `ZITADEL_MASTERKEY` (админ-пароль сразу
удовлетворяет политике сложности), а также каталоги `$APPS_STORAGE_PATH/zitadel/*`.
Либо вручную:

```sh
cd zitadel
cp .env.example .env
# заполнить POSTGRES_PASSWORD, ADMIN_PASSWORD, ZITADEL_MASTERKEY
docker compose config --quiet
docker compose up -d
docker compose ps
```

Админ логинится как `admin@zitadel.id.example.net` (org по умолчанию —
`zitadel`). Первый вход заставит сменить пароль. Если старт падает с ошибкой
password complexity — пароль не прошёл политику; миграция применяется частично,
поэтому `docker compose down -v`, поправить пароль и поднять заново.

Не менять `ZITADEL_MASTERKEY` после инициализации: им зашифрованы секреты,
замена ключа делает данные нечитаемыми.

## Passkey-only

См. `docs/research/authentication-services.md` (этап 2). Коротко: в
Organization Settings → Login Behavior and Security поставить «Passkey Login» =
Allowed; пользователей регистрировать только passkey (отдельная ссылка
регистрации), пароль не задавать. «Local authentication allowed» не выключать —
это отключит и passkey.

Одноразовую ссылку на регистрацию passkey без SMTP выдаёт
`scripts/zitadel-passkey-link.sh` (нужен PAT администратора):

```sh
ZITADEL_PAT=... ./scripts/zitadel-passkey-link.sh
```

## OIDC-клиент для oauth2-proxy

Для forward auth (см. `oauth2-proxy/`) создать в консоли ZITADEL приложение:

- Type: Web;
- Redirect URI: `https://oauth.example.net/oauth2/callback`;
- client_id и client_secret скопировать в `oauth2-proxy/.env`.

## Резервное копирование

```sh
cd /home/artlab/projects/homelab/zitadel
docker compose --profile tools run --rm backup-db
```

Restic сохраняет `$APPS_STORAGE_PATH/zitadel` и локальный `zitadel/.env`.

## Обновление

Проверять release notes: после 4.11 были passkey-регрессии (#11656, #11682),
в 4.16.1 — #12473. `ZITADEL_VERSION` закреплён в `.env`; контейнеры `zitadel` и
`login` должны обновляться одним тегом.

```sh
docker compose pull
docker compose up -d
docker compose ps
```

## Проверка

```sh
docker compose ps
docker logs --since=5m zitadel
docker logs --since=5m zitadel-login
```
