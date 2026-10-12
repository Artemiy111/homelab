# Zitadel: эксплуатация

## Первый вход

Админ логинится как `admin@zitadel.id.<домен>` (org по умолчанию —
`zitadel`). Принудительная смена пароля выключена
(`PASSWORDCHANGEREQUIRED=false`): пароль генерируется случайно и лежит в Vault,
менять его при первом входе не требуется.

## Passkey-only

См. `docs/research/authentication-services.md` (этап 2). Коротко: в
Organization Settings → Login Behavior and Security поставить «Passkey Login» =
Allowed; пользователей регистрировать только passkey (отдельная ссылка
регистрации), пароль не задавать. «Local authentication allowed» не выключать —
это отключит и passkey.

Одноразовую ссылку на регистрацию passkey без SMTP выдаёт
`zitadel/zitadel-passkey-link.sh` (нужен PAT администратора). Домен передаётся
переменной `DOMAIN` — тот же, что в бывшем чарте platform/homelab; вместо
неё можно задать `ZITADEL_HOST`:

```sh
DOMAIN=example.com ZITADEL_PAT=... ./zitadel/zitadel-passkey-link.sh
```

## Обновление

Проверять release notes: после 4.11 были passkey-регрессии (#11656, #11682),
в 4.16.1 — #12473. Версии `zitadel` и `login` закреплены в манифестах и должны
обновляться одним тегом.
