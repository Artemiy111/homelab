# Immich: эксплуатация

## Вход

OIDC через Zitadel. Объявлен в `manifests/config/system-config.yaml` и приезжает в
под файлом: интерфейс (Administration → Settings → Authentication → OAuth
Authentication) показывает те же значения, но менять их оттуда нельзя —
`IMMICH_CONFIG_FILE` делает конфиг файловым и правки в UI отклоняются.

Значения, объявленные в файле:

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
(`infra/casa/terraform/zitadel/applications.tf`), там же объявлены redirect URI:
`/auth/login`, `/user-settings`, `/api/oauth/mobile-redirect`.

`<домен>` в таблице — плейсхолдер для читателя: в самом файле домен стоит
буквально, как и в остальных манифестах стенда (`docs/adr/0009`). `client_id`
настоящий — он не секрет и лежит в state открытым текстом.

Дрейф возможен: если значения в файле разъедутся с таблицей, прав файл.

Смена домена стенда — это правка `oauth.issuerUrl` и `oauth.mobileRedirectUri` в
`manifests/config/system-config.yaml`. Файл читается только при старте, но
перезапускать под руками не нужно: kustomize собирает имя ConfigMap вместе с
хешем содержимого файла, поэтому ссылка в деплойменте меняется вместе с конфигом
и под перекатывается сам. Остаётся дождаться:

```sh
kubectl -n immich rollout status deploy/immich-server
```

Невалидный YAML не даст серверу подняться вовсе, поэтому проверять файл лучше
схемой из образа до мержа.

Команды `immich-admin enable-password-login` и `disable-oauth-login` пишут конфиг
в БД, а файл её перекрывает: с `IMMICH_CONFIG_FILE` они молча не влияют ни на что,
и аварийный вход тоже делается правкой файла. Пароля это не касается —
`immich-admin reset-admin-password` работает как обычно.

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
