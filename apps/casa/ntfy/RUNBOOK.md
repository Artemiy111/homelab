# ntfy: эксплуатация

## Проверка

```sh
curl -fsS https://ntfy.example.com/v1/health
```

Ожидается `{"healthy":true,...}`. Эндпоинт не трогает базу: без кластеризации
сервер здоров, пока отвечает.

```sh
kubectl -n ntfy get pods
kubectl -n ntfy logs deploy/ntfy --tail=20
```

Ожидается `Running`/`Ready` и строка о прослушивании адреса в логах.

## Модель доступа

Четыре проверки снаружи описывают всё, что открыто:

```sh
curl -s -o /dev/null -w 'read_up=%{http_code}\n' 'https://ntfy.example.com/uptest/json?poll=1'
curl -s -o /dev/null -w 'write_up=%{http_code}\n' -d test https://ntfy.example.com/uptest
curl -s -o /dev/null -w 'write_other=%{http_code}\n' -d test https://ntfy.example.com/other
curl -s -o /dev/null -w 'read_other=%{http_code}\n' 'https://ntfy.example.com/other/json?poll=1'
```

Ожидается `read_up=200`, `write_up=200`, `write_other=403`, `read_other=403`.

`/json?poll=1` обязателен: только JSON-эндпоинт проверяет ACL. Запрос без него —
`curl https://ntfy.example.com/uptest` — отдаёт веб-страницу ntfy со статусом
`200` на любой топик, даже запрещённый, и о правах не говорит ничего.

## Доставка от Synapse

```sh
kubectl -n element logs deploy/element-synapse --since=15m | grep -i push
```

Успешная доставка в логах молчит; видны только ошибки (`Failed to send push`).
Поэтому «Synapse доставил» подтверждается парой: в логах нет ошибок и
уведомление пришло на телефон.

Пушеры пользователя:

```sh
curl -fsS -H "Authorization: Bearer <admin-token>" \
  "https://element.example.com/_synapse/admin/v1/users/@<localpart>:<домен>/pushers" | jq
```

Ожидается запись с `kind: http` и `data.url`, указывающим на
`https://ntfy.example.com/up...`. Если admin-токена под рукой нет, то же видно в
базе:

```sh
kubectl exec -n databases shared-1 -c postgres -- \
  psql -U postgres -d synapse -c \
  "select user_id, app_id, kind, data from pushers;"
```

## Учётная запись на телефоне

Не нужна. Чтение `up*` открыто анонимно, как и запись, поэтому дистрибьютор
подписывается на capability URL без входа, а в настройках приложения достаточно
указать сервер `https://ntfy.example.com`.

Если ntfy понадобится вынести наружу, порядок обратный: сначала завести
пользователя с `read-only` на `up*`, потом закрыть анонимное чтение. Пользователя
из env (`NTFY_AUTH_USERS`, хеш из Vault) достаточно — `ntfy user add` не годится,
`auth-file` лежит в `emptyDir` и пересоздаётся вместе с подом.

## Что нужно на телефоне

1. Установить ntfy (F-Droid, Google Play или APK с релизов).
2. В настройках приложения указать сервер `https://ntfy.example.com`.
3. В Element X включить уведомления и выбрать ntfy дистрибьютором UnifiedPush.
4. Проверить: закрыть Element X, написать себе сообщение с другого клиента.
   Уведомление должно прийти в течение нескольких секунд.

## Обновление версии

Правится только тег и digest образа в `deployment.yaml`; Argo перекатывает под
сам. После переката `emptyDir` пустой, но терять нечего: ACL и пользователи
приходят из env, сообщения не персистятся. Проверить `/v1/health` и одно живое
уведомление.

## Известные сбои

`403` на запись в `up*` — не применился ACL: смотреть `NTFY_AUTH_ACCESS` в поде
и лог на старте, где ntfy печатает провижининг доступа.

Под в `CrashLoopBackOff` с ошибкой открытия `user.db` — проблема с томом:
`emptyDir` должен быть записываемым для группы (fsGroup), а корневая ФС —
только для чтения.

`502` от Traefik — под не `Ready`; смотреть `/v1/health` изнутри пода и логи.

Уведомления не приходят, а в базе pusher есть — проверять подписку
дистрибьютора: `read_up` из раздела проверки должен отдавать `200`, при `403`
подписчик не подключится и сообщение из памяти пропадёт.
