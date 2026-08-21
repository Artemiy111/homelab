# Zitadel

Zitadel — IdP homelab. Доступен через Traefik по `https://id.example.com/`;
- консоль — `/ui/console`
- вход — `/ui/v2/login`.

## Первый запуск

```sh
bash ./init.sh
docker compose up -d
```

Postgres поднимается с двумя ролями: суперпользователь (`POSTGRES_ADMIN_USER`,
нужен только для создания роли при инициализации, бэкапа и ручных работ) и
непривилегированный `POSTGRES_ZITADEL_USER` — владелец базы, под которым
работает ZITADEL. Роль создаёт `initdb/01-create-zitadel-user.sh`; скрипты из
`initdb/` выполняются только на пустом каталоге данных.

Админ логинится как `admin@zitadel.id.example.com` (org по умолчанию —
`zitadel`). Принудительная смена пароля выключена
(`PASSWORDCHANGEREQUIRED=false`): пароль генерируется случайно и лежит в
`.env`, менять его при первом входе не требуется.

`ZITADEL_FIRSTINSTANCE_*` применяется только на пустой базе.

Masterkey хранится не в `.env`, а отдельным файлом
`$APPS_STORAGE_PATH/zitadel/masterkey` (создаёт `init.sh`, права `0600`);
контейнер монтирует его read-only и читает через `--masterkeyFile`. Не менять
ключ после инициализации: им зашифрованы секреты, замена делает данные
нечитаемыми.

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
- Redirect URI: `https://oauth.example.com/oauth2/callback`;
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
