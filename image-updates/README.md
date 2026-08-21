# Обновления Docker images

WUD и Cup независимо проверяют образы запущенных Docker-контейнеров:

- WUD доступен по адресу `https://wud.example.com/`, хранит историю
  проверок и в дальнейшем может отправлять уведомления;
- Cup доступен по адресу `https://cup.example.com/` и предоставляет
  лёгкий интерфейс и JSON API `/api/v3/json`.

Оба приложения работают только в режиме наблюдения. Триггеры WUD не настроены,
а Docker API доступен им через отдельный read-only socket proxy, запрещающий
POST-запросы. Порт proxy и порты приложений на хосте не публикуются.

Интерфейсы защищены на Traefik через forward auth: middleware `oauth2-proxy@file`
проверяет сессионную cookie и при её отсутствии отправляет браузер на вход в
ZITADEL (`oauth2-proxy/README.md`). Отдельные секреты для этих интерфейсов не
нужны, в `.env` остаются только хосты.

## Запуск

`init.sh` создаёт каталог `$APPS_STORAGE_PATH/wud/store`, формирует `.env`
с хостами и заготовками для Docker Hub и рендерит `cup.json`. Из каталога
сервиса:

```sh
bash ./init.sh
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

## Конфигурация Cup

`cup.json` генерируется `init.sh` из `cup.json.tpl` (сам файл в `.gitignore`,
в Git только шаблон). Токен Docker Hub хранится исключительно в `.env`
(переменные `CUP_DOCKERHUB_USERNAME` / `CUP_DOCKERHUB_TOKEN`, PAT с правами
read-only) и не попадает в репозиторий: `init.sh` собирает из него строку
`base64(логин:токен)` и подставляет в блок `registries.registry-1.docker.io`.
Пока токен не задан, блок не рендерится и Cup работает анонимно (лимит
100 pulls/6h). После изменения токена выполните `bash image-updates/init.sh`
и `docker compose restart cup`.
