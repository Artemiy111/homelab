# MAS: эксплуатация

## Проверка

```sh
curl -fsS https://mas.example.com/.well-known/openid-configuration
```

Ожидается JSON с `"issuer":"https://mas.example.com/"` и
`authorization_endpoint`. По нему видно, что сервис жив: остальные публичные
ресурсы — редиректы на Zitadel и Admin API, который без токена отвечает `401`.

```sh
kubectl -n mas get pods
kubectl -n mas logs deploy/mas --tail=20
```

Ожидается `Running`/`Ready`; в логах — применение миграций БД и строка о
запуске листенеров.

## Admin API

```sh
curl -sS -o /dev/null -w '%{http_code}\n' https://mas.example.com/api/admin/v1/version
curl -sS -o /dev/null -w '%{http_code}\n' https://mas.example.com/api/spec.json
```

Ожидается `401` и `200`. `404` на первом — ресурс `adminapi` не добавлен в
`http.listeners[].resources` публичного листенера: тогда Element Admin
открывается, но данные MAS не грузятся.

## Администраторы

Права админа — это `can_request_admin` у пользователя MAS: с ним MAS выдаёт
скоупы `urn:mas:admin` и `urn:synapse:admin:*`, а без него — отказывает в них.

```sh
kubectl -n mas exec deploy/mas -- \
  mas-cli manage list-admin-users -c /etc/mas/config.yaml
kubectl -n mas exec deploy/mas -- \
  mas-cli manage promote-admin -c /etc/mas/config.yaml <username>
kubectl -n mas exec deploy/mas -- \
  mas-cli manage demote-admin -c /etc/mas/config.yaml <username>
```

Ожидается строка `username=<username>` в списке после `promote-admin`.
`promote-admin` включает `can_request_admin` в таблице `users`, схема БД не
меняется, перезапуск не нужен; уже выданные токены привилегий задним числом не
получают.

Отдельный вход в admin API без браузера — client credentials: клиент должен быть
в `policy.data.admin_clients`, скоуп запрашивается как `urn:mas:admin`.

```sh
curl -sS -u "<client_id>:<client_secret>" \
  -d 'grant_type=client_credentials&scope=urn:mas:admin' \
  https://mas.example.com/oauth2/token | jq -r .access_token
```

## Секреты

| Путь Vault | Ключи | Куда попадает |
|---|---|---|
| `kv/mas/db` | `username`, `password` | секрет `mas-db`, файл пароля для Postgres |
| `kv/mas/secrets` | `matrix_secret`, `encryption`, `rsa_key`, `ec_key` | `matrix.secret_file`, `secrets.*_file` |
| `kv/mas/oidc` | `client_secret` | `upstream_oauth2.providers[].client_secret_file` |

`client_id` приложения Zitadel секретом не является и лежит в `config.yaml`.

Проверить, что оператор разнёс секреты:

```sh
kubectl -n mas get vaultstaticsecret
kubectl -n mas get secret mas-db mas-secrets mas-oidc
```

Ожидается `Ready=True` у всех трёх и три секрета. Перечитать Vault, не дожидаясь
часа:

```sh
kubectl -n mas annotate vaultstaticsecret mas-oidc \
  vso.secrets.hashicorp.com/force-sync="$(date +%s)" --overwrite
```

`rolloutRestartTargets` в `VaultStaticSecret` перекатывает Deployment после
синка: ключи читаются на старте процесса, на лету MAS их не перечитывает.

## Ротация `client_secret`

1. Перевыпустить секрет приложения в Zitadel.
2. Положить новое значение в `kv/mas/oidc` (`client_secret`).
3. Дождаться синка `VaultStaticSecret` (или форсировать, см. выше) — под
   перезапустится сам.

## Известные сбои

`CreateContainerConfigError` — не хватает одного из трёх секретов. Смотреть
`kubectl -n mas describe pod` и статус `vaultstaticsecret`: чаще всего путь в
Vault ещё не заведён.

`502` от Traefik — под не `Ready`. Проверять `/health` на порту `8081` изнутри
пода и логи: при недоступной БД MAS не поднимется, миграции идут на старте.

Вход циклит между MAS и Zitadel — не совпал redirect URI: в Zitadel он должен
быть ровно `https://mas.example.com/upstream/callback/<ulid>`, где `<ulid>` —
`id` провайдера в `config.yaml`.
