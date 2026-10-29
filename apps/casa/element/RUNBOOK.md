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

### Звонки из интернета

Сначала — публичная запись: в зоне домена нет wildcard, каждый хост заводится
отдельно. Для TURN нужен `turn.<домен>` с адресом балансировщика, тот же, что у
`element.<домен>`. Выпуск сертификата от этой записи не зависит (DNS-01 сам
создаёт TXT), но звонок снаружи без неё не начнётся.

Внешнему клиенту нужен ещё и TURN, поэтому проверяется, что Synapse отдаёт
публичный адрес:

```sh
kubectl -n element exec deploy/element-synapse -c synapse -- \
  grep -A3 '^turn_uris' /etc/synapse/homeserver.yaml
```

Ожидаемый результат: первая строка — `turns:turn.<домен>:443?transport=tcp`,
за ней адреса для LAN. Конфиг Synapse на лету не перечитывается: после правки
`homeserver.yaml` под перезапускается руками.

```sh
kubectl -n element rollout restart deploy/element-synapse
```

Сертификат для coturn выпускает cert-manager, но под живёт и без него: coturn
пишет `Certificate file not found` и поднимает только незашифрованный TURN.
Звонки из LAN при этом работают, а снаружи срываются молча, поэтому проверка
идёт до звонка:

```sh
kubectl -n element get certificate element-turn-tls
kubectl -n element get secret element-turn-tls
```

Ожидаемый результат: `Ready=True` и Secret с ключами `tls.crt` и `tls.key`.

cert-manager обновляет Secret сам, а coturn читает сертификат только на старте
и перезагрузки не делает. После каждого обновления под перезапускается вручную,
иначе TLS будет отдавать сертификат, который уже заменён в Secret:

```sh
kubectl -n element rollout restart deploy/element-turn
```

TLS-порт coturn снаружи выглядит как `443` публичного входа. Проверяется
хендшейком на `turn.<домен>`, то есть через `casa-edge`, минуя Traefik:

```sh
openssl s_client -connect turn.<домен>:443 -servername turn.<домен> </dev/null | \
  openssl x509 -noout -subject -dates
```

Ожидаемый результат: сертификат на `turn.<домен>` от Let's Encrypt. Обрыв —
coturn не слушает TLS или SNI-ветка не сработала; сертификат на `*.<домен>`
того же происхождения означает, что соединение ушло в Traefik вместо coturn.
Если под coturn поднят, а порт всё равно закрыт, — смотреть firewalld на узле:
coturn публикует порт напрямую, мимо kube-proxy, и правило для `5349/tcp`
нужно отдельно.

Оба порта coturn видны в его конфиге:

```sh
kubectl -n element exec deploy/element-turn -- \
  grep -E '^(tls-)?listening-port' /etc/turn/turnserver.conf
```

Ожидаемый результат: `listening-port=3479` и `tls-listening-port=5349`.
