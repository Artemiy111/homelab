# Home Assistant

Home Assistant Container работает в сети хоста и использует адрес сервера.
URL: `https://ha.example.com`;

`network_mode: host` нужен для локального обнаружения устройств через mDNS,
SSDP и DHCP. Он также надёжнее отдельного `macvlan` на этом сервере: физическое
LAN-подключение использует Wi-Fi, а `macvlan` требует поддержки нескольких
MAC-адресов сетью и не позволяет контейнеру напрямую обращаться к хосту.

## Первый запуск

Все управляемые файлы (`configuration.yaml`, `automations.yaml`, `scripts.yaml`,
`scenes.yaml`) маунтятся из каталога сервиса; в `$APPS_STORAGE_PATH/home-assistant`
живёт собственное состояние HA (БД, `.storage`, blueprints, tts) и весь каталог
`custom_components/` (интеграции, в т.ч. поставленные HACS, и `auth_oidc` из
`init.sh`). Контейнер работает как root,
поэтому владелец каталога данных для него не важен. Из каталога сервиса:

```sh
bash scripts/bootstrap-platform.sh home-assistant
```

После запуска завершите onboarding в веб-интерфейсе. Постоянные данные находятся
в `$APPS_STORAGE_PATH/home-assistant` и входят в общий Restic snapshot.
Правки автоматизаций через UI попадают в `automations.yaml`/`scripts.yaml`
маунта — на сервере они видны как diff рабочей копии репозитория.

### HACS

[HACS](https://hacs.xyz) ставится в персистентный `custom_components/` (не через
Git — каталог компонентов целиком из `/storage`). HACS 2.x настраивается только
через UI и **не требует** блока в `configuration.yaml`. Первый запуск — в UI
(Settings → Devices & Services → Add Integration → HACS) и требует личный
GitHub Personal Access Token (нужен HACS для скачивания/обновления интеграций
с GitHub). Интеграции, поставленные HACS, живут там же и входят в Restic snapshot.

## Привилегии

Контейнер намеренно не использует `privileged: true`, Docker socket, D-Bus или
доступ ко всему `/dev`. Все стандартные capabilities сняты; возвращены только
`NET_RAW` (пассивный DHCP discovery и ICMP-интеграции) и `DAC_OVERRIDE`
(запись в artlab-owned мауты — автоматизации из UI и состояние в каталоге
данных — без подгона владельцев под root). `no-new-privileges` запрещает
получение дополнительных прав процессами в контейнере.

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
выполняются идемпотентным `init.sh` (скачивает релиз в `custom_components/`
персистентного каталога данных — `$APPS_STORAGE_PATH/home-assistant/custom_components`,
который целиком mount'ится в контейнер как `/config/custom_components`; повторный
запуск ничего не меняет). Креденшалы клиента (`OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`)
лежат в закоммиченном зашифрованном `secrets.enc.env` (SOPS + age) и попадают
в контейнер окружением (секреты в окружении через `service_run`);
`configuration.yaml` читает их через `!env_var`. Plaintext-файл секретов
на диске не создаётся.

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
2. Вписать креденшалы в зашифрованный secrets.enc.env (локально или на
   сервере; приватный age-ключ есть только на сервере):

```sh
sops home-assistant/secrets.enc.env
```

3. Установить интеграцию и проверить конфигурацию (версия берётся из
   `config.env`; повторный запуск ничего не переустанавливает):

```sh
cd /home/artlab/projects/homelab
source scripts/lib/common.sh && service_init home-assistant
docker compose --project-directory home-assistant exec home-assistant \
  python -m homeassistant --script check_config --config /config
```

`service_init` подмешивает `config.env` и расшифровывает `secrets.enc.env`,
после чего `init.sh` ставит компонент и рендерит `/config/secrets.yaml`.

4. Перезапустить и проверить вход:

```sh
docker compose --project-directory home-assistant restart home-assistant
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
закоммитить, на сервере `git pull --ff-only` и запустить
`bash scripts/bootstrap-platform.sh home-assistant` заново.
