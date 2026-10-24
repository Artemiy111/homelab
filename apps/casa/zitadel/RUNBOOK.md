# Zitadel: эксплуатация

## Первый вход

Админ логинится как `admin@zitadel.id.<домен>` (org по умолчанию —
`zitadel`). Принудительная смена пароля выключена
(`PASSWORDCHANGEREQUIRED=false`): пароль генерируется случайно и лежит в Vault,
менять его при первом входе не требуется.

## Passkey-only

Одноразовую ссылку на регистрацию passkey без SMTP выдаёт
`zitadel/zitadel-passkey-link.sh` (нужен PAT администратора). Домен передаётся
переменной `DOMAIN` — тот же, что hostname в Gateway
(`platform/casa/traefik/manifests/gateway-homelab.yaml`); вместо неё
можно задать `ZITADEL_HOST`:

```sh
DOMAIN=example.com ZITADEL_PAT=... ./zitadel/zitadel-passkey-link.sh
```

## Обновление

Проверять release notes: после 4.11 были passkey-регрессии (#11656, #11682),
в 4.16.1 — #12473. Версии `zitadel` и `login` закреплены в манифестах и должны
обновляться одним тегом. Раздел `Upgrade notes` читать целиком: в 4.20.0 это
подпись session cookie в Login V2 (все входят в UI заново) и
`ZITADEL_SESSION_COOKIE_SECRET`, который пока не задан — пока ключ выводится из
login-client, warning в логах `zitadel-login` ожидаем.

Перед merge минорного апгрейда:

1. Снять дамп базы: после миграций откат образом невозможен.

   ```sh
   kubectl -n zitadel exec zitadel-db-1 -c postgres -- \
     pg_dump -U postgres -d zitadel -Fc > ~/backups/zitadel/zitadel-pre-4.20.0.dump
   ```

2. Проверить, что узел резолвит внешние имена без кластера (docs/incidents/0012):

   ```sh
   dig +short ghcr.io; resolvectl dns enp2s0
   ```

   Если единственный резолвер — Technitium (`192.168.1.254`), pull нового
   образа может не состояться именно тогда, когда он нужен: оба пода со
   `strategy: Recreate` удаляются до загрузки образа.
