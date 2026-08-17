# High Performance Backend для Nextcloud Talk

Разворачивает официальный all-in-one контейнер
[`aio-talk`](https://github.com/nextcloud/all-in-one/tree/main/Containers/talk):
внутри одного контейнера работают spreed-signaling server (путь
`/standalone-signaling`), Janus MCU/SFU, NATS и eturnal TURN/STUN. Это включает
серверное перекодирование и раздачу видео: вместо прямых P2P-соединений между
участниками трафик идёт через сервер, поэтому качество больше не ограничено
слабым клиентом-участником, а для больших звонков хватает одного восходящего
потока на участника.

Адрес: `https://talk-signaling.example.net/standalone-signaling`
(SFTP-адрес для настроек Talk). TURN/STUN слушает `192.0.2.10:3478`.

## Топология

- Signaling (HTTP/WS) проходит через Traefik: `Host(talk-signaling.*) +
  PathPrefix(/standalone-signaling)` → контейнер `8081`. Публикуется порт `3478`
  (tcp+udp) для TURN/STUN.
- Пиhole-запись `address=/example.net/192.0.2.10` уже покрывает
  поддомен `talk-signaling`, wildcard-сертификат Traefik тоже существует — новых
  DNS/TLS-записей не требуется.
- Внутри контейнера relay-адреса eturnal привязаны к адресу контейнера, поэтому
  для клиентов за NAT важен проброс `3478/udp` (см. «Сетевая модель»).

## Подготовка

На сервере выполнить:

```sh
cd /home/artlab/projects/homelab/talk-hpb
./init.sh
docker compose pull
docker compose up -d
docker compose ps
```

`init.sh` создаёт игнорируемый `.env` с правами `0600` и случайными секретами.
Повторный запуск не перезаписывает существующие секреты. Проект также входит в
общий оркестратор инициализации `bash scripts/bootstrap-platform.sh`.

## Настройка Nextcloud Talk

Проксирование через Traefik настраивается автоматически по лейблам compose.
Остаётся зарегистрировать HPB в самом Talk (выполняется на сервере):

```sh
TALK_SECRET=$(grep -E '^SIGNALING_SECRET=' /home/artlab/projects/homelab/talk-hpb/.env | cut -d= -f2-)
TURN_SECRET=$(grep -E '^TURN_SECRET=' /home/artlab/projects/homelab/talk-hpb/.env | cut -d= -f2-)

docker exec -u www-data nextcloud-app php occ talk:signaling:add \
  https://talk-signaling.example.net/standalone-signaling "$TALK_SECRET" --verify

docker exec -u www-data nextcloud-app php occ talk:stun:add \
  talk-signaling.example.net:3478

docker exec -u www-data nextcloud-app php occ talk:turn:add \
  turn,turns talk-signaling.example.net udp,tcp --secret="$TURN_SECRET"
```

Проверить, что серверы зарегистрированы:

```sh
docker exec -u www-data nextcloud-app php occ talk:signaling:list
docker exec -u www-data nextcloud-app php occ talk:stun:list
docker exec -u www-data nextcloud-app php occ talk:turn:list
```

## Firewall

Открыть `3478/tcp` и `3478/udp` в firewalld для доверенных зон (LAN/tailnet),
иначе клиенты не пройдут NAT к TURN/STUN:

```sh
sudo firewall-cmd --permanent --add-port=3478/tcp
sudo firewall-cmd --permanent --add-port=3478/udp
sudo firewall-cmd --reload
```

Сигнальный порт `8081` наружу не публикуется — только через Traefik на 443.

## Проверка

```sh
dig +short @192.0.2.10 talk-signaling.example.net A
curl --resolve talk-signaling.example.net:443:192.0.2.10 \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://talk-signaling.example.net/standalone-signaling/api/v1/welcome
docker compose ps
docker compose logs --since=5m
```

Ожидаются DNS-ответ `192.0.2.10`, HTTP `200`, контейнер в статусе healthy.
Полная проверка — звонок между двумя устройствами: HTTP-ответ не подтверждает
работу UDP-медиатрафика.

## Сетевая модель

- TCP `443` завершается на Traefik и ведёт на `8081` с префиксом
  `/standalone-signaling`.
- UDP/TCP `3478` привязан к `192.0.2.10` и передаётся eturnal (TURN+STUN).
- Janus принимает медиа изнутри; адреса relay eturnal приватные, поэтому для
  внешних участников необходим проброс `3478/udp` на роутере и открытый порт в
  firewalld. Без него звонки проходят только внутри локальной сети и tailnet.

SELinux и firewalld не отключать.

## Обновление

Менять `TALK_IMAGE_VERSION` одновременно в `init.sh`, `.env.example` и серверном
`.env`, затем пересоздать контейнер (`docker compose up -d`) и повторить проверку
звонка. Секреты в `.env` при этом не трогать.
