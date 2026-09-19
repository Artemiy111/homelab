# Beszel

Beszel собирает метрики хоста и Docker-контейнеров, хранит историю и отправляет
уведомления. 
URL: `https://beszel.example.com/`

Разворачивается манифестами в apps/beszel/k8s/.

## Первый запуск

Откройте URL и создайте администратора. Затем:

1. В Settings → Tokens создайте universal token.
2. Запишите значения в `secrets.enc.env`:

```dotenv
BESZEL_AGENT_KEY='ssh-ed25519 AAAA...'
BESZEL_AGENT_TOKEN='секретный-токен'
```

Если система не добавилась автоматически, создайте её через Add System и укажите
`/beszel_socket/beszel.sock` как Host / IP. После запуска проверьте
HTTPS-маршрут:

```sh
curl -fsS https://beszel.example.com/api/health
```

## Superuser панели /_

PocketBase-панель (`/_/`) — отдельный аккаунт, не связанный с hub-пользователем.

Доступ Agent к `/var/run/docker.sock` даёт ему широкие права над Docker daemon,
даже если сокет смонтирован только для чтения. Используйте только доверенный
официальный образ и обновляйте закреплённую версию вместе с digest.
