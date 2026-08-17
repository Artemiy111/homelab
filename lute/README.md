# Lute

Lute — веб-приложение для чтения и изучения иностранных языков (Language
Utilities for Tracking Exposure). Контейнер доступен только через Traefik по
адресу `https://lute.example.net/`; порт приложения напрямую на хост не
публикуется. Внутри контейнера приложение слушает порт `5001`. Постоянные данные
находятся в `$APPS_STORAGE_PATH/lute/data`.

## Запуск

Создайте `.env` с именем хоста (используется в правиле маршрутизации Traefik):

```sh
cp .env.example .env
chmod 600 .env
install -d ${APPS_STORAGE_PATH:-/storage/apps}/lute/data/data ${APPS_STORAGE_PATH:-/storage/apps}/lute/data/backups
docker compose config --quiet
docker compose up -d
docker compose ps
```

Доступ к приложению идёт через `traefiknet`; на хосту должна быть запись DNS
`lute.example.net` -> адрес сервера.

## Понижение привилегий

Образ не умеет работать от не-root через `user: "1000:1000"`: на старте он пишет
во внутренний каталог `/pythainlp-data`, владелец которого в образе root, от uid
1000 туда нет доступа (`PermissionError: '/pythainlp-data'`). Поэтому контейнер
запускается от root.

При этом применяется «точечное» деление привилегий: `cap_drop: ALL` с возвратом
единственной нужной capability — `CAP_DAC_OVERRIDE`. Она требуется, потому что
хостовый каталог данных `$APPS_STORAGE_PATH/lute/data` принадлежит uid 1000, а
контейнер-root без `CAP_DAC_OVERRIDE` не может в него писать
(`sqlite3.OperationalError: attempt to write a readonly database`). Остальные
capability сброшены, понижая поверхность атаки по сравнению с исходным запуском от
root со всеми capability по умолчанию.

Также задействован `security_opt: label:disable` (SELinux-метка) и добавлен
healthcheck по `http://127.0.0.1:5001/`.
