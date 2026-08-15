# Обновления Docker images

WUD и Cup независимо проверяют образы запущенных Docker-контейнеров:

- WUD доступен по адресу `https://wud.example.net/`, хранит историю
  проверок и в дальнейшем может отправлять уведомления;
- Cup доступен по адресу `https://cup.example.net/` и предоставляет
  лёгкий интерфейс и JSON API `/api/v3/json`.

Оба приложения работают только в режиме наблюдения. Триггеры WUD не настроены,
а Docker API доступен им через отдельный read-only socket proxy, запрещающий
POST-запросы. Порт proxy и порты приложений на хосте не публикуются.

Интерфейсы защищены общей HTTP Basic-аутентификацией на Traefik. Секреты
хранятся только в локальном `.env`; файл `.env.example` содержит заглушки.

## Запуск

Первичная подготовка всего homelab создаёт каталог данных, `.env` и случайный
пароль автоматически:

```sh
bash scripts/bootstrap-platform.sh
```

Для ручной подготовки только этого проекта:

```sh
sudo install -d -m 0750 /storage/apps/wud/store
cp .env.example .env
password="$(openssl rand -hex 24)"
hash="$(printf '%s' "$password" | openssl passwd -apr1 -stdin)"
sed -i "s|^UPDATES_DASHBOARD_PASSWORD=.*|UPDATES_DASHBOARD_PASSWORD=$password|" .env
sed -i "s|^UPDATES_DASHBOARD_USERS=.*|UPDATES_DASHBOARD_USERS='admin:$hash'|" .env
chmod 600 .env
docker compose config --quiet
docker compose up -d
docker compose ps
```

Пароль можно прочитать на сервере без вывода остальных переменных:

```sh
sed -n 's/^UPDATES_DASHBOARD_PASSWORD=//p' .env
```

Проверки выполняются при первом запуске, а затем каждые шесть часов. Чтобы
исключить отдельный контейнер из WUD, добавьте ему label:

```yaml
labels:
  - wud.watch=false
```

Изменение версии образа и пересоздание контейнера выполняются через Git и
`docker compose`, а не из интерфейсов WUD или Cup.
