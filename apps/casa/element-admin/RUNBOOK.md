# Element Admin: эксплуатация

## Проверка на стенде

```sh
kubectl -n argocd get application element-admin
kubectl -n element-admin get pods
```

Ожидается `Synced`/`Healthy` и под `Running`/`Ready`.

```sh
kubectl -n element-admin port-forward svc/element-admin 8080:80
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/health
```

Ожидается `200`. Так же проверяет Gatus — публичный хост закрыт forward-auth и на
`/health` отвечает редиректом.

```sh
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' \
  https://element-admin.<домен>/
```

Ожидается `302` на `https://oauth.<домен>/oauth2/start?...` — это признак того,
что маршрут и `oauth2-proxy` на месте. `200` здесь означал бы, что middleware в
`HTTPRoute` не смонтировался.

## MAS Admin API

Без него панель открывается, но данные MAS не показывает.

```sh
curl -sS -o /dev/null -w '%{http_code}\n' https://mas.<домен>/api/admin/v1/version
```

Ожидается `401` — API включён и просит токен. `404` — в `http.listeners` MAS нет
ресурса `adminapi` (публичный листенер `web`, `apps/casa/mas`).

```sh
curl -sS -D- -o /dev/null -X OPTIONS https://mas.<домен>/api/admin/v1/version \
  -H 'Origin: https://element-admin.<домен>' \
  -H 'Access-Control-Request-Method: GET' | grep -i access-control
```

Ожидается `access-control-allow-origin: *`. Если заголовка нет, браузер
покажет CORS-ошибку в консоли, и панель не загрузит данные MAS.

То же для Synapse:

```sh
curl -sS -D- -o /dev/null -X OPTIONS https://element.<домен>/_synapse/admin/v1/server_version \
  -H 'Origin: https://element-admin.<домен>' \
  -H 'Access-Control-Request-Method: GET' | grep -i access-control
```

## Права администратора

Флаг живёт в MAS, а не в Synapse.

```sh
kubectl -n mas exec deploy/mas -- mas-cli manage list-admin-users -c /etc/mas/config.yaml
kubectl -n mas exec deploy/mas -- mas-cli manage promote-admin -c /etc/mas/config.yaml <username>
```

Ожидается строка `username=<username>` в списке после `promote-admin`.
`demote-admin` снимает флаг.

Флаг действует на следующие входы: старый токен, выданный до повышения, привилегий
не получит.

## Вход

1. Открыть `https://element-admin.<домен>/` — редирект на Zitadel.
2. Войти в Zitadel, затем подтвердить доступ в MAS (согласие на скоупы
   `urn:synapse:admin:*`, `urn:mas:admin`).
3. В панели должны открыться списки пользователей MAS и комнат Synapse.

Если после согласия панель пустая, а в консоли браузера `403` — у пользователя
нет `can_request_admin` (см. выше). Если `404` на `/api/admin/...` — не включён
`adminapi` в MAS.

## Известные сбои

| Симптом | Что смотреть |
|---|---|
| Под в `CrashLoopBackOff` | `kubectl -n element-admin logs deploy/element-admin --previous`; чаще всего не смонтирован `/tmp` при `readOnlyRootFilesystem` |
| `502` на маршруте | `kubectl -n element-admin get endpoints element-admin` — пустой список значит, что под не прошёл readiness |
| `500`/`502` после входа | логи `deploy/oauth2-proxy` в namespace `oauth2-proxy` |
| Панель не находит homeserver | `curl -fsS https://<домен>/.well-known/matrix/client` — apex обязан отдавать `m.homeserver` |
| CORS-ошибка в консоли | preflight-проверки выше; для MAS — ресурс `adminapi` и `Origin` |
| Отказ на запросе скоупа в MAS | `can_request_admin` у пользователя и `policy.data.admin_users` в конфиге MAS |
| Редирект после логина уводит на `oauth.<домен>` | `--reverse-proxy=true` у oauth2-proxy и `X-Forwarded-*` от Traefik |

## Обновление версии

Тег и дайджест меняются вместе: дайджест — от мультиарх-индекса, не от
платформенного манифеста.

```sh
curl -sS -D- -o /dev/null \
  -H 'Accept: application/vnd.oci.image.index.v1+json' \
  https://oci.element.io/v2/element-admin/manifests/<тег> | grep -i docker-content-digest
```

Дайджест вписывается в `image` рядом с тегом. Откат — вернуть предыдущую пару
«тег + дайджест» и засинкать Application.

## Удаление

```sh
kubectl -n argocd delete application element-admin
kubectl delete ns element-admin
```

Namespace помечен `Prune=false`, поэтому Argo его не удаляет — это делается
руками. Ресурс `adminapi` в MAS можно оставить: он ничего не открывает без
скоупа, а следующий инструмент для админ-API всё равно понадобится.
