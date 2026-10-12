# Home Assistant: эксплуатация

## Первый запуск

После запуска завершите onboarding в веб-интерфейсе. Постоянные данные находятся
в персистентном каталоге данных сервиса.

### HACS

[HACS](https://hacs.xyz) ставится в персистентный `custom_components/` (не через
Git — каталог компонентов целиком из storage). HACS 2.x настраивается только
через UI и **не требует** блока в `configuration.yaml`. Первый запуск — в UI
(Settings → Devices & Services → Add Integration → HACS) и требует личный
GitHub Personal Access Token (нужен HACS для скачивания/обновления интеграций
с GitHub). Интеграции, поставленные HACS, живут там же.

## Проверка

```sh
curl --resolve ha.example.com:443:<node1-ip> \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://ha.example.com/
```

Прямой доступ к `http://<node1-ip>:8123` блокируется firewalld; для работы
интерфейса он не нужен, поскольку входящий HTTPS уже обслуживает Traefik.

## Восстановление доступа

Если SSO сломался, доступ восстанавливается на сервере: вернуть локальный
провайдер правкой `configuration.yaml` (`git revert && git pull` или sed) и
перезапустить сервис.

Полное пересоздание HA: онбординг HA жёстко требует локального провайдера
(создаёт владельца с паролем), поэтому перед ним нужно временно заменить
`auth_providers: []` на `- type: homeassistant`, пройти онбординг и выдать
права администратора OIDC-пользователю, затем вернуть конфиг.

## Первоначальная настройка SSO

Находясь на сервере:

1. В ZITADEL Console создать проект «Home Assistant» и приложение:
   тип **Web**, auth method **CODE**, redirect URI
   `https://ha.example.com/auth/oidc/callback`; сохранить
   ClientID/ClientSecret (секрет показывается один раз).
2. Вписать креденшалы в Vault по путям `kv/home-assistant/oidc`
   (client_id) и `kv/home-assistant/@hacs/hacs-secret` (client_secret).

3. Перезапустить сервис и проверить вход:

```sh
curl -fsSL -o /dev/null -w '%{http_code} %{redirect_url}\n' \
  https://ha.example.com/
```

Открыть `https://ha.example.com/` — браузер должен уйти на
ZITADEL и вернуться в HA под пользователем ZITADEL.

4. Выдать права администратора первому OIDC-пользователю. Пока пароль отключён,
   админа в системе нет, поэтому один раз временно вернуть локальный вход:
   закомментировать блок `homeassistant: auth_providers: []` в
   `configuration.yaml`, закоммитить, на сервере `git pull --ff-only` и
   перезапустить сервис. Зайти старым локальным админом,
   в Settings → Users повысить OIDC-пользователя до администратора, затем
   вернуть конфиг и перезапустить ещё раз.
