# Beszel

Beszel собирает метрики хоста и Docker-контейнеров, хранит историю и отправляет
уведомления. Hub доступен через Traefik по адресу
`https://beszel.example.com/`; порты Hub и Agent на хосте не
публикуются.

Постоянные данные находятся в `$APPS_STORAGE_PATH/beszel`. Локальный Agent использует
Unix-сокет для связи с Hub и подключает Docker socket с флагом `ro`. Из-за
`network_mode: host` Agent также видит сетевые интерфейсы хоста.

## Первый запуск

Сначала запустите только Hub. Из каталога `beszel` выполнить:

```sh
bash ./init.sh
docker compose up -d
```

`init.sh` создаёт каталоги `data`, `agent` и `socket` и заготовку `.env`.

Откройте `https://beszel.example.com/` и создайте администратора. Затем:

1. В Settings → Tokens создайте universal token.
2. Нажмите Add System и скопируйте public key.
3. Запишите значения в локальный `.env`:

```dotenv
BESZEL_AGENT_KEY='ssh-ed25519 AAAA...'
BESZEL_AGENT_TOKEN='секретный-токен'
```

Запустите Agent:

```sh
docker compose --profile agent up -d
```

Если система не добавилась автоматически, создайте её через Add System и укажите
`/beszel_socket/beszel.sock` как Host / IP. После запуска проверьте оба
контейнера и HTTPS-маршрут:

```sh
docker compose --profile agent ps
curl -fsS https://beszel.example.com/api/health
```

## Superuser панели /_

PocketBase-панель (`/_/`) — отдельный аккаунт, не связанный с hub-пользователем.
Создать или сбросить пароль:

```sh
bash ./superuser.sh <email>
```

Пароль генерируется случайно и печатается один раз.

Файл `.env` не отслеживается Git. Не добавляйте public key и token в
`.env.example` или Compose-конфигурацию.

Подключение `/var/run/docker.sock` даёт Agent широкие права над Docker daemon,
даже если bind mount помечен `ro`. Используйте только доверенный официальный
образ и обновляйте закреплённую версию вместе с digest.
