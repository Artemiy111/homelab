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

## Ключ подписи cookie (Login V2)

Login V2 подписывает session cookie и короткоживущие proof'ы (подтверждение
почты и инвайта, привязка IdP, device code) ключом
`ZITADEL_SESSION_COOKIE_SECRET` — `kv/zitadel/session-cookie`, ключ `secret`.
Требования: не короче 32 символов, одинаковое значение на всех репликах.
Короткое значение не откатывается на fallback: под пишет ошибку и не проходит
`/ready`.

Ротация без разлогина — списком: первым идёт новое значение (им подписываем),
дальше старые (ими ещё принимаем).

```sh
# 1. Новое значение первым, старое вторым
vault kv patch kv/zitadel/session-cookie secret="<новое>,<старое>"

# 2. Дождаться, пока VSO перезапишет Secret (refreshAfter 1h, можно форсировать)
kubectl -n zitadel annotate vaultstaticsecret zitadel-session-cookie \
  vso.secrets.hashicorp.com/force-sync="$(date +%s)" --overwrite

# 3. Перезапустить под: значение читается из env при старте
kubectl -n zitadel delete pod -l app=zitadel-login

# 4. Через 24 часа (максимальная жизнь сессии) убрать старое значение
vault kv patch kv/zitadel/session-cookie secret="<новое>"
```

## Обновление

Проверять release notes: после 4.11 были passkey-регрессии (#11656, #11682),
в 4.16.1 — #12473. Версии `zitadel` и `login` закреплены в манифестах и должны
обновляться одним тегом. Раздел `Upgrade notes` читать целиком: в 4.20.0 это
подпись session cookie в Login V2 — все пользователи входят в UI заново.

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

## База недоступна

Готовность базы перед стартом пода больше не проверяет init-контейнер: порядок
задают волны Argo, а ZITADEL, потерявший базу, завершается и перезапускается с
backoff. Поэтому `CrashLoopBackOff` у `deploy/zitadel` — это в первую очередь
проверка базы, а не приложения.

```sh
kubectl -n zitadel get cluster zitadel-db
kubectl -n zitadel get databases.postgresql.cnpg.io zitadel
kubectl -n zitadel logs deploy/zitadel --since=5m | grep -iE "postgres|database"
```

Ожидаемо: `Cluster in healthy state`, `APPLIED = true` у базы. Ошибки
соединения в логах ZITADEL указывают на кластер; успешные миграции — на то, что
идёт обычный старт (после апгрейда он бывает долгим).

## Terraform падает с 404 на v1 API

Провайдер Terraform для `zitadel_action`, `zitadel_instance_member`,
`zitadel_org_member`, `zitadel_project_role`, `zitadel_user_grant`,
`zitadel_login_policy` и `zitadel_organization_domain` ходит в legacy v1 API по
настоящему gRPC, а gRPC требует HTTP/2. ZITADEL отдаёт v1 только по gRPC и REST:
Connect/JSON-транспорт для него убран в v4. Если Traefik идёт к поду по
HTTP/1.1, каждый такой ресурс получает `404 Not Found` с content-type
`application/json`, а провайдер показывает это как `rpc error: code =
Unimplemented ... unexpected content-type`.

Поэтому порт `http` в `zitadel.service.yaml` помечен `appProtocol:
kubernetes.io/h2c` — по этому полю Gateway API провайдер Traefik выбирает схему
бэкенда. Без него v2-ресурсы продолжают работать (Connect переживает HTTP/1.1),
а v1 падают, и это выглядит как расхождение state, а не как проблема прокси.

```sh
kubectl -n zitadel get svc zitadel -o jsonpath='{.spec.ports[0].appProtocol}'
```

Ожидаемо: `kubernetes.io/h2c`. Пропал — значит Argo не досинхронизировал
Service, и `terraform plan` снова покажет 404 на v1-ресурсах.

