# Home Assistant

Home Assistant Container работает в сети хоста и использует адрес сервера. Интерфейс доступен через Traefik по адресу
`https://ha.example.com`;

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
curl --resolve ha.example.com:443:192.0.2.10 \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://ha.example.com/
docker logs --since=5m home-assistant 2>&1
```

Прямой доступ к `http://192.0.2.10:8123` блокируется firewalld; для работы
интерфейса он не нужен, поскольку входящий HTTPS уже обслуживает Traefik.

## SSO через ZITADEL

Аутентификация делегирована ZITADEL (`id.example.com`) через кастомную
интеграцию [hass-oidc-auth](https://github.com/christiaangoossens/hass-oidc-auth)
(`auth_oidc` в `configuration.yaml`). Вход по паролю отключён полностью
(`homeassistant: auth_providers: []`) — войти можно только через ZITADEL,
в том числе из мобильных приложений (OIDC-браузер).

Интеграция ставится не через HACS: версия пинируется переменной
`HOME_ASSISTANT_OIDC_VERSION` в закоммиченном `config.env`, установка и обновление
выполняются идемпотентным `init.sh` (скачивает релиз в
`$APPS_STORAGE_PATH/home-assistant/custom_components/auth_oidc`, повторный запуск
ничего не меняет). Креденшалы клиента — в
`$APPS_STORAGE_PATH/home-assistant/secrets.yaml` (не трекается, входит в Restic
snapshot): `oidc_client_id`, `oidc_client_secret`.

Права: новый пользователь ZITADEL при первом входе получает обычную (не
админскую) учётку HA, привязанную к его subject в ZITADEL. Автоматически
админом никто не становится. Выдача прав — вручную через Settings → Users
из сессии существующего админа либо через роли (`roles:` + groups claim,
см. доки интеграции). Если SSO сломался, доступ восстанавливается на сервере:
вернуть локальный провайдер правкой `configuration.yaml`
(`git revert && git pull` или sed) и перезапустить контейнер.

Полное пересоздание HA: онбординг HA жёстко требует локального провайдера
(создаёт владельца с паролем), поэтому перед ним нужно временно заменить
`auth_providers: []` на `- type: homeassistant`, пройти онбординг и выдать
права администратора OIDC-пользователю, затем вернуть конфиг.

### Первоначальная настройка

Находясь на сервере:

1. В ZITADEL Console создать проект «Home Assistant» и приложение:
   тип **Web**, auth method **CODE**, redirect URI
   `https://ha.example.com/auth/oidc/callback`; сохранить
   ClientID/ClientSecret (секрет показывается один раз).
2. Вписать креденшалы в secrets.yaml:

```sh
SECRETS="$APPS_STORAGE_PATH/home-assistant/secrets.yaml"
touch "$SECRETS" && chmod 600 "$SECRETS"
cat >>"$SECRETS" <<EOF
oidc_client_id: ВСТАВЬ_CLIENT_ID
oidc_client_secret: ВСТАВЬ_CLIENT_SECRET
EOF
```

3. Установить интеграцию и проверить конфигурацию (версия берётся из
   `config.env`; повторный запуск ничего не переустанавливает):

```sh
cd /home/artlab/projects/homelab/home-assistant
set -a && . ./config.env && set +a
bash ./init.sh
docker compose exec home-assistant \
  python -m homeassistant --script check_config --config /config
```

4. Перезапустить и проверить вход:

```sh
docker compose restart home-assistant
curl -fsSL -o /dev/null -w '%{http_code} %{redirect_url}\n' \
  https://ha.example.com/
```

Открыть `https://ha.example.com/` — браузер должен уйти на
ZITADEL и вернуться в HA под пользователем ZITADEL.

5. Выдать права администратора первому OIDC-пользователю. Пока пароль отключён,
   админа в системе нет, поэтому один раз временно вернуть локальный вход:
   закомментировать блок `homeassistant: auth_providers: []` в
   `configuration.yaml`, закоммитить, на сервере `git pull --ff-only` и
   `docker compose restart home-assistant`. Зайти старым локальным админом,
   в Settings → Users повысить OIDC-пользователя до администратора, затем
   вернуть конфиг и перезапустить ещё раз.

Обновление интеграции: поменять `HOME_ASSISTANT_OIDC_VERSION` в `config.env`,
закоммитить, на сервере `git pull --ff-only` и запустить `bash ./init.sh`
заново, затем рестарт контейнера.
