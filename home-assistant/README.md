# Home Assistant

Home Assistant Container работает в сети хоста и использует адрес сервера. Интерфейс доступен через Traefik по адресу
`https://homeassistant.example.com`;

`network_mode: host` нужен для локального обнаружения устройств через mDNS,
SSDP и DHCP. Он также надёжнее отдельного `macvlan` на этом сервере: физическое
LAN-подключение использует Wi-Fi, а `macvlan` требует поддержки нескольких
MAC-адресов сетью и не позволяет контейнеру напрямую обращаться к хосту.

## Первый запуск

`init.sh` создаёт `.env` с хостом и каталог конфигурации
`$APPS_STORAGE_PATH/home-assistant`. Home Assistant работает как root внутри
контейнера, но без Linux capabilities, кроме `NET_RAW`; поэтому каталог заранее
получает нужные владельца, права и стартовые файлы через отдельный одноразовый
контейнер. Из каталога сервиса:

```sh
bash ./init.sh
bash ./init-postinstall.sh
docker compose up -d
docker compose ps
```

После запуска завершите onboarding в веб-интерфейсе. Постоянные данные находятся
в `$APPS_STORAGE_PATH/home-assistant` и входят в общий Restic snapshot.

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
docker compose exec home-assistant \
  python -m homeassistant --script check_config --config /config
curl --resolve homeassistant.example.com:443:192.0.2.10 \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://homeassistant.example.com/
docker logs --since=5m home-assistant 2>&1
```

Прямой доступ к `http://192.0.2.10:8123` блокируется firewalld; для работы
интерфейса он не нужен, поскольку входящий HTTPS уже обслуживает Traefik.
