# Zitadel

Zitadel — IdP homelab. Доступен через Traefik по `https://id.example.com/`;
- консоль — `/ui/console`
- вход — `/ui/v2/login`.

## Первый запуск

Разворачивается манифестами в `apps/zitadel/k8s/`.

Postgres поднимается кластером CloudNativePG: суперпользователь остаётся у
оператора, а ZITADEL работает под непривилегированной managed-ролью `zitadel` —
владельцем базы. Роль и база объявлены в `platform/cnpg/`
(`zitadel-db.cluster.yaml`, `zitadel-db.databases.yaml`).

Админ логинится как `admin@zitadel.id.example.com` (org по умолчанию —
`zitadel`). Принудительная смена пароля выключена
(`PASSWORDCHANGEREQUIRED=false`): пароль генерируется случайно и лежит в
зашифрованных секретах, менять его при первом входе не требуется.

`ZITADEL_FIRSTINSTANCE_*` применяется только на пустой базе.

Masterkey хранится отдельным файлом `/storage/apps/zitadel/masterkey`
(права `0600`); контейнер монтирует его read-only и читает через
`--masterkeyFile`. Не менять
ключ после инициализации: им зашифрованы секреты, замена делает данные
нечитаемыми.

## Passkey-only

См. `docs/research/authentication-services.md` (этап 2). Коротко: в
Organization Settings → Login Behavior and Security поставить «Passkey Login» =
Allowed; пользователей регистрировать только passkey (отдельная ссылка
регистрации), пароль не задавать. «Local authentication allowed» не выключать —
это отключит и passkey.

Одноразовую ссылку на регистрацию passkey без SMTP выдаёт
`zitadel/zitadel-passkey-link.sh` (нужен PAT администратора):

```sh
ZITADEL_PAT=... ./zitadel/zitadel-passkey-link.sh
```

## OIDC-клиент для oauth2-proxy

Для forward auth (см. `oauth2-proxy/`) создать в консоли ZITADEL приложение:

- Type: Web;
- Redirect URI: `https://oauth.example.com/oauth2/callback`;
- client_id и client_secret скопировать в `apps/oauth2-proxy/secrets.enc.env`.

## Обновление

Проверять release notes: после 4.11 были passkey-регрессии (#11656, #11682),
в 4.16.1 — #12473. Версии `zitadel` и `login` закреплены в манифестах и должны
обновляться одним тегом.
