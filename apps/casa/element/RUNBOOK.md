# Element / Matrix: эксплуатация

## Первый администратор

Публичная регистрация отключена, вход идёт через OIDC-провайдера Zitadel.
Учётка появляется при первом входе: localpart собирается из email
(`user_mapping_provider.localpart_template`), домен берётся из `server_name`.

Администраторов Synapse конфигом объявлять не умеет: флаг `admin` ставится либо
при создании учётки через shared-secret регистрацию, либо через Admin API уже
существующим администратором. Поэтому администратора создают один раз — **до**
первого входа через провайдера и с тем же localpart, который соберёт шаблон:
вход подхватит существующую учётку (`allow_existing_users`), и права сохранятся.

```sh
kubectl exec -i -n element deploy/element-synapse -c synapse -- sh -s <<'EOS'
set -eu
SECRET=$(tr -d '\r\n' < /run/secrets/element/registration_shared_secret)
PW=$(head -c 32 /dev/urandom | base64 | tr -d '\n')
register_new_matrix_user -k "$SECRET" -u admin -p "$PW" -a --exists-ok http://localhost:8080
EOS
```

Ожидаемый результат: `Success!`, при уже существующей учётке —
`User already exists. Skipping.`. Пароль генерируется случайным и нигде не
сохраняется: вход только через провайдера.

Проверка — флаг в базе:

```sh
kubectl exec -n databases shared-1 -c postgres -- \
  psql -U postgres -d synapse -c "select name, admin from users;"
```

Ожидаемый результат: одна строка `@admin:example.com | t`.

После входа под этой учёткой в Element появляются разделы администратора
сервера. В списке сеансов останется устройство `register_new_matrix_user` — след
бутстрапа, сессию надо завершить.

Если база `synapse` пересоздана, администратор пропадает вместе с ней: команду
надо выполнить снова, до первого входа через провайдера. Если вход случился
раньше, появится обычная учётка, и повысить её сможет только другой
администратор.

## Проверка

```sh
curl -fsS https://element.example.com/_matrix/client/versions
curl -fsS https://element.example.com/livekit/jwt/healthz
```

Полная проверка Element Call требует двух авторизованных клиентов в LAN или
tailnet: создать комнату, начать звонок и проверить аудио/видео.

Секреты и конфиги, собранные из Vault:

```sh
kubectl exec -n element deploy/element-synapse -c synapse -- \
  python -m synapse.config -c /etc/synapse/homeserver.yaml
kubectl exec -n element deploy/element-turn -- \
  grep -c '^static-auth-secret=' /etc/turn/turnserver.conf
kubectl exec -n element deploy/matrix-rtc-auth -- env | sort | grep LIVEKIT_
```

Ожидаемый результат: `Config parses OK!`; `1`; пути `LIVEKIT_KEY_FROM_FILE` и
`LIVEKIT_SECRET_FROM_FILE`, а не сами ключи.

Порядок и изоляция подов:

```sh
kubectl -n element get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].securityContext.readOnlyRootFilesystem}{"\n"}{end}'
kubectl -n element get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.initContainers}{"\n"}{end}'
```

Ожидаемый результат: у каждого пода `true` и пустой список init-контейнеров.

## Element Call

`matrix-rtc-auth` проверяет OpenID-токен пользователя в federation API Synapse.
Адрес он берёт из `https://example.com/.well-known/matrix/server`: Synapse
отдаёт `{"m.server":"example.com:443"}`, то есть запрос уходит на apex-домен.
Отсюда две зависимости, без которых звонок не начинается: apex резолвится
(A-запись Technitium) и на apex есть маршрут `/_matrix` (`element-well-known`
HTTPRoute). Симптом поломки — `OPEN_ID_ERROR` в Element и
`OpenIDUserInfo: Failed to look up user info` в логах `matrix-rtc-auth`.

```sh
curl -fsS https://example.com/.well-known/matrix/server
curl -sS -o /dev/null -w '%{http_code}\n' \
  'https://example.com/_matrix/federation/v1/openid/userinfo?access_token=x'
```

Ожидаемый результат: `{"m.server":"example.com:443"}` и `401`. Невалидный токен
Synapse отвергает; `404` значит, что маршрута на apex нет, transport error —
apex не резолвится.

Второй режим отказа выглядит иначе: Element показывает бесконечную загрузку,
ошибки в интерфейсе нет. Виджет Element Call живёт во фрейме того же origin,
поэтому звонок не начнётся, если прокси запрещает фрейм. Проверять надо
заголовок виджет-документа, а не SFU и не токены:

```sh
curl -sI https://element.example.com/widgets/element-call/index.html | grep -i x-frame-options
```

Ожидаемый результат: `x-frame-options: SAMEORIGIN` (значение задаёт
`secure-headers` на entrypoint Traefik, см. `platform/casa/traefik/README.md`).
`DENY` блокирует виджет на любом origin.

Подтверждение, что дело в клиенте, а не в сервисах: в access-логе Traefik по
`/livekit/sfu/rtc` нет ни одного `101`, а по `/livekit/jwt/sfu/get` — ни одного
`POST` от браузера. Ассеты `/widgets/element-call/assets/*` при этом тоже не
запрашиваются: заблокированный документ не доходит до разбора.
