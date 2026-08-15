# Home Assistant

Home Assistant Container работает в сети хоста и использует адрес сервера
`192.0.2.10`. Интерфейс доступен через Traefik по адресу
`https://homeassistant.example.net`; отдельный адрес
`192.0.2.10` не назначается. Traefik разрешает доступ к этому маршруту только
из локальной сети `192.0.2.10/24`, чтобы незавершённый onboarding не был виден
из интернета.

`network_mode: host` нужен для локального обнаружения устройств через mDNS,
SSDP и DHCP. Он также надёжнее отдельного `macvlan` на этом сервере: физическое
LAN-подключение использует Wi-Fi, а `macvlan` требует поддержки нескольких
MAC-адресов сетью и не позволяет контейнеру напрямую обращаться к хосту.

## Первый запуск

Создайте `.env` и принадлежащий root каталог конфигурации. Home Assistant
работает как root внутри контейнера, но без Linux capabilities, кроме
`NET_RAW`; поэтому каталог заранее создаётся отдельным одноразовым контейнером.

```sh
cp .env.example .env
chmod 0600 .env
mkdir -p /storage/apps/home-assistant
docker run --rm \
  --cap-drop ALL \
  --cap-add CHOWN \
  --security-opt no-new-privileges:true \
  -v /storage/apps/home-assistant:/config:Z \
  alpine:3.23 \
  sh -ec 'chown 0:0 /config; chmod 0700 /config;
    test -e /config/automations.yaml || printf "[]\n" > /config/automations.yaml;
    test -e /config/scripts.yaml || printf "{}\n" > /config/scripts.yaml;
    test -e /config/scenes.yaml || printf "[]\n" > /config/scenes.yaml'
docker compose config --quiet
docker compose up -d
docker compose ps
```

После запуска завершите onboarding в веб-интерфейсе. Постоянные данные находятся
в `/storage/apps/home-assistant` и входят в общий Restic snapshot.

## Привилегии

Контейнер намеренно не использует `privileged: true`, Docker socket, D-Bus или
доступ ко всему `/dev`. Все стандартные capabilities сняты; возвращён только
`NET_RAW`, необходимый пассивному DHCP discovery и интеграциям, использующим
ICMP. `no-new-privileges` запрещает получение дополнительных прав процессами
в контейнере.

Локальный Bluetooth сейчас намеренно не подключён. Вместо `default_config`
явно перечислены его стандартные зависимости, кроме `bluetooth`, чтобы Home
Assistant не пытался использовать встроенный `hci0` без необходимых прав. Для
полного Bluetooth нужно вернуть интеграцию, открыть read-only доступ к
`/run/dbus` и добавить capabilities `NET_ADMIN` и `NET_RAW`. `NET_ADMIN`
особенно чувствителен при `network_mode: host`, поскольку позволяет контейнеру
менять сетевые настройки хоста. Если появится Zigbee/Z-Wave USB-стик, следует
пробросить только конкретный `/dev/ttyUSB*` или `/dev/ttyACM*`, а не включать
privileged mode.

## Проверка

```sh
docker compose ps
docker compose exec homeassistant \
  python -m homeassistant --script check_config --config /config
curl --resolve homeassistant.example.net:443:192.0.2.10 \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://homeassistant.example.net/
docker logs --since=5m homeassistant 2>&1
```

Прямой доступ к `http://192.0.2.10:8123` блокируется firewalld; для работы
интерфейса он не нужен, поскольку входящий HTTPS уже обслуживает Traefik.
