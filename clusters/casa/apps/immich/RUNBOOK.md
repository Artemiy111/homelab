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

## Рекомендации VPA

Для `immich-server` и `immich-machine-learning` включён режим наблюдения:
рекомендации собираются, поды не меняются.

```sh
kubectl -n immich get vpa
kubectl -n immich describe vpa immich-server | sed -n '/Recommendation/,/Events/p'
kubectl -n immich describe vpa immich-machine-learning | sed -n '/Recommendation/,/Events/p'
```

Ожидаемо: в каждом — блок `Recommendation` с `Target`, `Lower Bound` и
`Upper Bound` по `cpu` и `memory`. Пустой блок — либо под молодой (рекомендация
набирается часами), либо недоступен Metrics API: `kubectl top pods -n immich`.

Сравнивать рекомендацию с тем, что реально стоит в поде:

```sh
kubectl -n immich get pod -l app=immich-server -o jsonpath='{.items[0].spec.containers[0].resources}{"\n"}'
kubectl -n immich get pod -l app=immich-machine-learning -o jsonpath='{.items[0].spec.containers[0].resources}{"\n"}'
```

Пока `updateMode` остаётся `"Off"`, источник правды — цифры в деплойменте:
рекомендация на них не влияет. Переносить её в манифест имеет смысл вручную и
осознанно: у сервера это ещё и перезапуск (`strategy: Recreate`).

## Диагностика

```sh
kubectl -n immich get pods
kubectl -n immich logs deploy/immich-server --since=10m
kubectl -n immich get vaultstaticsecret immich-db
```

Если вход не работает, проверь в Zitadel, что у пользователя есть роль в
проекте Homelab: без неё `addRole` кладёт `user`, и Immich не пустит в админку.
