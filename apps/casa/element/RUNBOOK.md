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
SECRET=$(sed -n 's/^registration_shared_secret: *//p' /data/homeserver.yaml)
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
