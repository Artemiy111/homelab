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

```sh
bash scripts/bootstrap-platform.sh image-updates
```
> Любые последующие команды `docker compose` этого сервиса требуют того же окружения:
> выполняйте их через `bash scripts/compose-secrets.sh image-updates …` или повторным
> `bash scripts/bootstrap-platform.sh image-updates`.


Проверки Cup выполняются при первом запуске, далее обновления запрашиваются
вручную кнопкой refresh в его интерфейсе: автоинтервал отключён, потому что Cup
падал (exit code 1) на ошибках registry при автоматическом refresh. Локально
собранные образы исключены из проверок через `images.exclude` в `cup.json`.
Чтобы исключить отдельный контейнер из WUD, добавьте ему label:

```yaml
labels:
  - wud.watch=false
```

Изменение версии образа и пересоздание контейнера выполняются через Git и
`docker compose`, а не из интерфейсов WUD или Cup.

## Конфигурация Cup

`cup.json` генерируется `init.sh` из `cup.tpl.json`. Токен Docker Hub хранится исключительно в `.env`
(переменные `CUP_DOCKERHUB_USERNAME` / `CUP_DOCKERHUB_TOKEN`, PAT с правами
read-only) и не попадает в репозиторий: `init.sh` собирает из него строку
`base64(логин:токен)` и подставляет в блок `registries.registry-1.docker.io`.
Пока токен не задан, блок не рендерится и Cup работает анонимно (лимит
100 pulls/6h). После изменения токена выполните `bash image-updates/init.sh`
и `docker compose restart cup`.
