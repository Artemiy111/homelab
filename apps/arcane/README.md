# Arcane

Arcane — веб-интерфейс управления Docker.
URL: `https://arcane.example.com/`

Контейнер Arcane стартует от root (так требует образ), затем понижает права до `PUID`/`PGID` (1000), поэтому в отличие от
простых сервисов ему не задаётся `cap_drop: ALL` — для понижения привилегий
нужны `CAP_SETUID`/`CAP_SETGID`. Self-upgrade не используется: обновления идут
по общему процессу (закрепление версии и digest образа в `compose.yaml`).

## Первый запуск

Из корня репозитория:

```sh
bash scripts/bootstrap-platform.sh arcane
```
> Любые последующие команды `docker compose` этого сервиса требуют того же окружения:
> выполняйте их через `bash scripts/compose-secrets.sh arcane …` или повторным
> `bash scripts/bootstrap-platform.sh arcane`.


Откройте URL и войдите под учётными данными
по умолчанию (`arcane` / `arcane-admin`); при первом входе Arcane потребует
сменить пароль.

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

Restic сохраняет `$APPS_STORAGE_PATH/arcane/data`; зашифрованный `secrets.enc.env`
уже в Git. Потеря `ENCRYPTION_KEY` делает данные Arcane недоступными,
поэтому он должен входить в защищённую копию конфигурации сервера.

## Обновление

Перед обновлением создайте согласованный backup. Затем закрепите новую версию
и digest образа в `compose.yaml`, проверьте release notes и выполните:

```sh
docker compose pull
docker compose up -d
docker compose ps
```
