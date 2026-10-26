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

Три проверки снаружи описывают всё, что открыто:

```sh
curl -s -o /dev/null -w 'read=%{http_code}\n' 'https://ntfy.example.com/uptest/json?poll=1'
curl -s -o /dev/null -w 'write_up=%{http_code}\n' -d test https://ntfy.example.com/uptest
curl -s -o /dev/null -w 'write_other=%{http_code}\n' -d test https://ntfy.example.com/other
```

Ожидается `read=403`, `write_up=200`, `write_other=403`. Первая проверка идёт
GET-ом на несуществующий топик: `403`, а не `404`, — это ACL отказывает раньше,
чем сервер смотрит на топик.

Запрос без `/json?poll=1` проверяет не API, а веб-интерфейс: на любой топик
`curl https://ntfy.example.com/<топик>` отдаёт `200` со статической страницей
ntfy, которая данных не содержит и не показывает, разрешено ли чтение.

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

## Учётная запись для телефона

Запись в `up*` открыта анонимно, чтение — нет. Значит, приложению-дистрибьютору
нужна учётная запись ntfy с `read-only` на `up*`, иначе оно получает `403` на
подписку, уведомления до ntfy доходят, но на телефон не приходят. Сейчас учётки
нет, провижининг — issue #1615.

Заводить её вручную бесполезно: `auth-file` лежит в `emptyDir`, поэтому
`ntfy user add` живёт до первого перезапуска пода. Правильный путь — хеш из
Vault в `NTFY_AUTH_USERS` (`<user>:<hash>:user`) плюс `<user>:up*:read-only` в
`NTFY_AUTH_ACCESS`: пользователи из env провижинятся при каждом старте и
переживают пересоздание тома. Хеш печатает `ntfy user hash`, пароль вводится
интерактивно и в историю шелла не попадает.

## Что нужно на телефоне

1. Установить ntfy (F-Droid, Google Play или APK с релизов).
2. В настройках приложения указать сервер `https://ntfy.example.com`.
3. Войти под учётной записью из раздела выше (её заводит issue #1615).
4. В Element X включить уведомления и выбрать ntfy дистрибьютором UnifiedPush.
5. Проверить: закрыть Element X, написать себе сообщение с другого клиента.
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
дистрибьютора: без входа в приложении ntfy чтение `up*` запрещено.
