# Jitsi Meet: эксплуатация

## Учётная запись организатора

Комнату открывает только аутентифицированный пользователь; остальные входят
гостями по ссылке. Логин — `admin` (в поле имени домен не вводится, клиент
дописывает `meet.jitsi`), пароль лежит в Vault по пути `kv/jitsi/auth` под
ключом `JITSI_MODERATOR_PASSWORD` и приходит в контейнер prosody переменной
окружения, поэтому в командной строке пароль не появляется.

Регистрация:

```sh
kubectl -n jitsi exec deploy/jitsi-prosody -c prosody -- \
  sh -c 'prosodyctl --config /run/prosody/config/prosody.cfg.lua \
    register admin meet.jitsi "$JITSI_MODERATOR_PASSWORD"'
```

Учётная запись лежит в томе `jitsi-prosody-storage`: перезапуск пода её не
сносит, а удаление тома — сносит.

Ротация пароля: обновить значение в Vault, форсировать синхронизацию секрета,
перезапустить prosody (переменная окружения читается при старте пода) и задать
тот же пароль учётной записи — `passwd` спросит его дважды:

```sh
kubectl -n jitsi exec -it deploy/jitsi-prosody -c prosody -- \
  prosodyctl --config /run/prosody/config/prosody.cfg.lua passwd admin@meet.jitsi
```

## Проверка

```sh
dig +short @<node1-ip> meet.example.com A
curl --resolve meet.example.com:443:<node1-ip> \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://meet.example.com/
curl --resolve meet.example.com:443:<node1-ip> \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://meet.example.com/xmpp-websocket
```

Ожидаются DNS-ответ `<node1-ip>`, HTTP `200` на главной и `200` на
`/xmpp-websocket`. Ответ `502` на XMPP-пути означает, что nginx в `jitsi-web`
не достучался до prosody: смотреть ошибки резолва в логах `jitsi-web`, а не
сеть между браузером и сервером.

Работающие контейнеры `web`, `prosody`, `jicofo` и `jvb` — часть той же
проверки. Полная проверка требует звонка между двумя устройствами: HTTP и
WebSocket не подтверждают прохождение UDP-медиатрафика.
