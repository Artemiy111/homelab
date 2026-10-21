# Troubleshoot: `OPEN_ID_ERROR` при создании звонка в Element

Дата: 2026-10-21

## Симптом

При попытке начать видеозвонок Element показывает «Произошла непредвиденная
ошибка» с кодом `OPEN_ID_ERROR` и техническими деталями:

```
MatrixError: [401] The request could not be authorised.
(https://element.biplane.casa/livekit/jwt/sfu/get)
```

Остальной Element работает: вход, комнаты, сообщения.

## Быстрый диагноз

`/livekit/jwt` обслуживает `matrix-rtc-auth` (lk-jwt-service). `sfu/get`
отдаёт `401`, когда не смог проверить OpenID-токен пользователя. Смотреть надо
логи сервиса, а не клиент:

```sh
kubectl -n element logs deploy/matrix-rtc-auth --tail=20
```

```
ERROR lk_jwt_service::helper: OpenIDUserInfo: Failed to look up user info
err=error sending request for url
(https://biplane.casa:8448/_matrix/federation/v1/openid/userinfo?access_token=…):
client error (Connect): dns error: failed to lookup address information:
Name has no usable address
```

`Name has no usable address` — не TLS и не 401 от Synapse: имя вообще не
резолвится. Обрати внимание на порт `8448` и имя `biplane.casa` вместо
`element.biplane.casa`.

## Откуда берётся адрес

Сервис проверяет токен в federation API homeserver'а. Server name он берёт из
самого OpenID-токена (`matrix_server_name` = `server_name` Synapse), а адрес
federation API — из delegation:

```sh
curl -sS --resolve 'biplane.casa:443:192.168.1.254' \
  https://biplane.casa/.well-known/matrix/server
# {"m.server":"biplane.casa:443"}
```

Synapse (`serve_server_wellknown: true`) объявляет federation на
`<server_name>:443`, потому что у server_name нет явного порта. Порт `8448`
в логе — это fallback lk-jwt-service на случай, когда well-known не удалось
прочитать: `https://<server_name>:8448`.

## Корень проблемы

Apex-домен `biplane.casa` не обслуживался вообще:

- в зоне Technitium есть только wildcard `*.biplane.casa`, а он не покрывает
  apex — A-записи `biplane.casa` не было (`dig biplane.casa A` → `NOERROR`,
  пустой ответ, SOA зоны);
- на слушателе `apex` Gateway `homelab` были только два точных маршрута
  `/.well-known/matrix/{client,server}`, маршрута `/_matrix` не было: даже при
  резолве federation endpoint отдавал `404`.

Поэтому lk-jwt-service падал в fallback на `biplane.casa:8448` — имя без
DNS-записи и без слушателя на порту.

Проверка второй половины проблемы (резолв в обход DNS, маршрута ещё нет):

```sh
curl -sS --resolve 'biplane.casa:443:192.168.1.254' -o /dev/null -w '%{http_code}\n' \
  'https://biplane.casa/_matrix/federation/v1/openid/userinfo?access_token=x'
# 404
```

Та же delegation нужна не только выдаче токенов: по ней lk-jwt-service находит
CS API для delegated leave (MSC4140), так что страдали и фоновые задачи звонков.

## Что сделано

- `infra/casa/terraform/technitium/records.tf` — A-запись apex-домена на адрес
  сервера (`technitium_record.apex`), wildcard её не заменяет;
- `apps/casa/element/chart/templates/route.yaml` — в `element-well-known`
  HTTPRoute добавлен `PathPrefix /_matrix` на Synapse для apex-хоста: именно
  туда ведёт `m.server`;
- `apps/casa/gatus/manifests/config/config.yaml` — проверка
  `https://<домен>/.well-known/matrix/server`: раньше отказ delegation не был
  виден ни одному монитору.

TLS и слушатель менять не пришлось: сертификат `wildcard-casa` уже содержит
apex в SAN, слушатель `apex` на 443 уже объявлен.

## Проверка

```sh
dig +short biplane.casa A                              # адрес сервера
curl -fsS https://biplane.casa/.well-known/matrix/server
curl -sS -o /dev/null -w '%{http_code}\n' \
  'https://biplane.casa/_matrix/federation/v1/openid/userinfo?access_token=x'
```

Ожидается адрес сервера, `{"m.server":"biplane.casa:443"}` и `401` от Synapse.
Затем — звонок между двумя клиентами и пустые логи `matrix-rtc-auth` по
`OpenIDUserInfo`.

## Уроки

- `serve_server_wellknown` ссылается на apex-домен, а не на `element.…`:
  публикация delegation — это DNS-запись и маршрут, а не только конфиг Synapse.
- Health-probe (`/healthz`) у `matrix-rtc-auth` зелёный при полностью нерабочей
  выдаче токенов: проверять надо внешнюю зависимость, а не процесс.
- Wildcard `*.domain` не покрывает `domain` — это же ломало бы любой сервис,
  объявленный на apex.
