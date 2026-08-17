# Обновления Docker images

WUD и Cup независимо проверяют образы запущенных Docker-контейнеров:

- WUD доступен по адресу `https://wud.example.net/`, хранит историю
  проверок и в дальнейшем может отправлять уведомления;
- Cup доступен по адресу `https://cup.example.net/` и предоставляет
  лёгкий интерфейс и JSON API `/api/v3/json`.

Оба приложения работают только в режиме наблюдения. Триггеры WUD не настроены,
а Docker API доступен им через отдельный read-only socket proxy, запрещающий
POST-запросы. Порт proxy и порты приложений на хосте не публикуются.

Интерфейсы защищены на Traefik через forward auth: middleware `oauth2-proxy@file`
проверяет сессионную cookie и при её отсутствии отправляет браузер на вход в
ZITADEL (`oauth2-proxy/README.md`). Отдельные секреты для этих интерфейсов не
нужны, в `.env` остаются только хосты.

## Запуск

Первичная подготовка всего homelab создаёт каталог данных и `.env`
автоматически:

```sh
bash scripts/bootstrap-platform.sh
```

Для ручной подготовки только этого проекта:

```sh
sudo install -d -m 0750 /storage/apps/wud/store
cp .env.example .env
chmod 600 .env
docker compose config --quiet
docker compose up -d
docker compose ps
```

Проверки Cup выполняются при первом запуске, далее обновления запрашиваются
вручную кнопкой refresh в его интерфейсе: автоинтервал отключён, потому что Cup
падал (exit code 1) на ошибках registry при автоматическом refresh. Локально
собранные образы (например, `structurizr-structurizr`) исключены из проверок
через `images.exclude` в `cup.json`. Чтобы исключить отдельный контейнер из
WUD, добавьте ему label:

```yaml
labels:
  - wud.watch=false
```

Изменение версии образа и пересоздание контейнера выполняются через Git и
`docker compose`, а не из интерфейсов WUD или Cup.
