# High Performance Backend для Nextcloud Talk: эксплуатация

## Firewall

Открыть `3478/tcp` и `3478/udp` в firewalld для доверенных зон (LAN/tailnet),
иначе клиенты не пройдут NAT к TURN/STUN:

```sh
sudo firewall-cmd --permanent --add-port=3478/tcp
sudo firewall-cmd --permanent --add-port=3478/udp
sudo firewall-cmd --reload
```

Сигнальный порт `8081` наружу не публикуется — только через Traefик на 443.

## Проверка

```sh
dig +short @<node1-ip> talk-signaling.example.com A
curl --resolve talk-signaling.example.com:443:<node1-ip> \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://talk-signaling.example.com/standalone-signaling/api/v1/welcome
```

Ожидаются DNS-ответ `<node1-ip>` и HTTP `200`.
Полная проверка — звонок между двумя устройствами: HTTP-ответ не подтверждает
работу UDP-медиатрафика.
