# Immich: эксплуатация

## Вход

OIDC через Zitadel. Настраивается **в интерфейсе** — Administration →
Settings → Authentication → OAuth Authentication.

Значения, заданные в UI:

| Поле | Значение |
|---|---|
| Issuer URL | `https://id.<домен>` |
| Client ID | `388541482971234332` |
| Scope | `openid email profile` |
| Storage label claim | `preferred_username` |
| Role claim | `role` |
| Auto register | вкл. |
| Mobile redirect URI override | вкл. |
| Mobile redirect URI | `https://immich.<домен>/api/oauth/mobile-redirect` |

Client ID соответствует приложению `immich` в Zitadel
(`infra/terraform/zitadel/applications.tf`), там же объявлены redirect URI:
`/auth/login`, `/user-settings`, `/api/oauth/mobile-redirect`.

`<домен>` — плейсхолдер: реальный корневой домен лежит в
`infra/terraform/zitadel/terraform.tfvars` (untracked) и по
`docs/agents/information-handling.md` в git не пишется. `client_id` в таблице
при этом настоящий — он не секрет и в state лежит открытым текстом.

Дрейф возможен: если перенастроить OIDC в UI, поправь таблицу выше.

## Проверка настройки

```sh
kubectl -n immich logs deploy/immich-server --since=5m | grep -i oauth
```

Значения в UI: Administration → Settings → Authentication.

## Диагностика

```sh
kubectl -n immich get pods
kubectl -n immich logs deploy/immich-server --since=10m
kubectl -n immich get vaultstaticsecret immich-db
```

Если вход не работает, проверь в Zitadel, что у пользователя есть роль в
проекте Homelab: без неё `addRole` кладёт `user`, и Immich не пустит в админку.
