# Jitsi Meet: эксплуатация

## Учётная запись организатора

Создать пользователя, которому разрешено открывать новые комнаты.
Первый участник входит с этой учётной записью и создаёт комнату; остальные подключаются как гости по ссылке.

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
