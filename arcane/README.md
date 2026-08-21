# Arcane

Arcane — веб-интерфейс управления Docker: контейнеры, образы, сети, тома и
stacks. Интерфейс доступен через Traefik по адресу
`https://arcane.example.com/`; порт 3552 на хосте не публикуется.

Docker доступен не напрямую, а через ограниченный `docker-socket-proxy`
(та же схема, что в `image-updates/`): прокси подключает `docker.sock` только
для чтения и разрешает Arcane ограниченный набор операций API (контейнеры,
образы, сети, тома, exec, POST). Секции `AUTH`, `SECRETS`, `BUILD`, `COMMIT`,
`CONFIGS`, `NODES`, `PLUGINS`, `SERVICES`, `SESSION`, `SWARM`, `SYSTEM`,
`TASKS` остаются закрытыми.

Постоянные данные находятся в `$APPS_STORAGE_PATH/arcane/data`; SELinux-доступ
обеспечивается меткой `:Z`. Контейнер Arcane стартует от root (так требует
образ), затем понижает права до `PUID`/`PGID` (1000), поэтому в отличие от
простых сервисов ему не задаётся `cap_drop: ALL` — для понижения привилегий
нужны `CAP_SETUID`/`CAP_SETGID`. Self-upgrade не используется: обновления идут
по общему процессу (закрепление версии и digest образа в `compose.yaml`).

## Первый запуск

Из каталога `arcane` выполнить:

```sh
bash ./init.sh
docker compose pull
docker compose up -d
docker compose ps
```

`init.sh` создаёт каталоги данных и `.env`. Откройте `https://arcane.example.com/` и войдите под учётными данными
по умолчанию (`arcane` / `arcane-admin`); при первом входе Arcane потребует
сменить пароль. Секреты `ENCRYPTION_KEY` и `JWT_SECRET` генерирует `init.sh`,
они хранятся только в локальном `arcane/.env` (в Git не попадают).

## Проверка

```sh
docker compose ps
curl --resolve arcane.example.com:443:192.0.2.10 \
  -fsS https://arcane.example.com/api/health
docker logs --since=5m arcane 2>&1
```

Health endpoint должен вернуть `200`. Docker-соединение идёт через
`tcp://docker-socket-proxy:2375`; в логах при старте должен появиться успешный
коннект к Docker daemon. Убедиться, что Arcane видит и может управлять
контейнерами, можно в интерфейсе (список контейнеров и действия
start/stop/restart).

## Резервное копирование

Для согласованного снимка SQLite остановите Arcane на время общего Restic
backup:

```sh
cd /home/artlab/projects/homelab/arcane
docker compose stop arcane
cd ../restic
docker compose run --rm backup
cd ../arcane
docker compose start arcane
```

Restic сохраняет и `$APPS_STORAGE_PATH/arcane/data`, и локальный `arcane/.env` из
рабочей копии. Потеря `ENCRYPTION_KEY` делает данные Arcane недоступными,
поэтому `.env` должен входить в защищённую копию конфигурации сервера.

## Обновление

Перед обновлением создайте согласованный backup. Затем закрепите новую версию
и digest образа в `compose.yaml`, проверьте release notes и выполните:

```sh
docker compose pull
docker compose up -d
docker compose ps
```
