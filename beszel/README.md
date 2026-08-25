# Beszel

Beszel собирает метрики хоста и Docker-контейнеров, хранит историю и отправляет
уведомления. 
URL: `https://beszel.example.com/`

## Первый запуск

Сначала запустите только Hub. Из каталога `beszel` выполнить:

```sh
bash ./init.sh
docker compose up -d
```

Откройте URL и создайте администратора. Затем:

1. В Settings → Tokens создайте universal token.
2. Запишите значения в `secrets.enc.env`:

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

Подключение `/var/run/docker.sock` даёт Agent широкие права над Docker daemon,
даже если bind mount помечен `ro`. Используйте только доверенный официальный
образ и обновляйте закреплённую версию вместе с digest.
