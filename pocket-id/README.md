# Pocket ID

Pocket ID предоставляет локальный OpenID Connect provider с аутентификацией по
passkey. Интерфейс и OIDC endpoints доступны через Traefik по адресу
`https://pocket-id.example.com/`; порт контейнера на хосте не публикуется.

Сервис использует SQLite и хранит базу, ключи подписи и загруженные файлы в
`$APPS_STORAGE_PATH/pocket-id/data`. Контейнер запускается без root, с read-only root
filesystem и принимает proxy headers только от CIDR сети `traefiknet`.
Незашифрованные callback URL запрещены, кроме loopback URL, которые Pocket ID
разрешает для локальных клиентов.

## Первый запуск

```sh
bash ./init.sh
docker compose up -d
docker compose ps
```

`init.sh` создаёт каталог данных с правами `0700`, формирует независимый ключ
шифрования в локальном `pocket-id/.env` и проверяет Compose-конфигурацию.
Секрет не попадёт в Git.

Откройте `https://pocket-id.example.com/setup`, создайте администратора и сразу
зарегистрируйте как минимум две passkey на разных устройствах. Pocket ID не
поддерживает вход по паролю. Самостоятельная регистрация пользователей по
умолчанию отключена; дополнительных пользователей создавайте в панели
администратора либо через одноразовые signup links.

Ключ `ENCRYPTION_KEY` шифрует в том числе приватные ключи OIDC. Его потеря
сделает зашифрованные данные недоступными, поэтому `.env` должен входить в
защищённую копию конфигурации сервера.

## Проверка

```sh
docker compose ps
curl --resolve pocket-id.example.com:443:192.0.2.10 \
  -fsS https://pocket-id.example.com/.well-known/openid-configuration
docker logs --since=5m pocket-id 2>&1
```

OIDC discovery должен вернуть JSON с issuer
`https://pocket-id.example.com`. После первоначальной настройки добавьте
декларативный монитор в Uptime Kuma:

```sh
cd /home/artlab/projects/homelab/uptime-kuma
docker compose --profile tools run --rm configure
```

## Резервное копирование

Для согласованного снимка SQLite остановите Pocket ID на время общего Restic
backup:

```sh
cd /home/artlab/projects/homelab/pocket-id
docker compose stop pocket-id
cd ../restic
docker compose run --rm backup
cd ../pocket-id
docker compose start pocket-id
```

Restic сохраняет и `$APPS_STORAGE_PATH/pocket-id/data`, и локальный `.env` из рабочей
копии репозитория. Локальный Restic repository находится на том же физическом
диске и не защищает от его поломки или потери.

Перед восстановлением остановите контейнер и сначала восстановите snapshot в
изолированный каталог. Не копируйте файлы поверх рабочего каталога без проверки
содержимого и отдельного backup текущего состояния.

Если все passkey администратора потеряны, одноразовый код можно выпустить из
терминала сервера:

```sh
docker compose exec pocket-id /app/pocket-id one-time-access-token USER_OR_EMAIL
```

Код является секретом: передайте его только нужному пользователю и используйте
для регистрации новой passkey.

## Обновление

Перед обновлением создайте согласованный backup. Затем закрепите новую версию и
digest образа в `compose.yaml`, проверьте release notes и выполните:

```sh
docker compose pull
docker compose up -d
docker compose ps
```
