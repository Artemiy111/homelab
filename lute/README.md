# Lute

Lute — веб-приложение для чтения и изучения иностранных языков (Language
Utilities for Tracking Exposure). Контейнер доступен только через Traefik по
адресу `https://lute.example.net/`; порт приложения напрямую на хост не
публикуется. Внутри контейнера приложение слушает порт `5001`. Постоянные данные
находятся в `/storage/apps/lute/data`.

## Запуск

Создайте `.env` с именем хоста (используется в правиле маршрутизации Traefik):

```sh
cp .env.example .env
chmod 600 .env
install -d /storage/apps/lute/data/data /storage/apps/lute/data/backups
docker compose config --quiet
docker compose up -d
docker compose ps
```

Доступ к приложению идёт через `traefiknet`; на хосту должна быть запись DNS
`lute.example.net` -> адрес сервера.

## Почему нельзя просто снять привилегии

Прямое понижение прав для этого образа ломает запуск:

- `user: "1000:1000"` — приложение на старте пишет во внутренний каталог
  `/pythainlp-data`, владелец которого в образе root. От uid 1000 туда доступа
  нет, получаем `PermissionError: '/pythainlp-data'` и выход.
- `cap_drop: ALL` при работе от root — хостовый каталог данных
  `/storage/apps/lute/data` принадлежит uid 1000, а контейнер-root без
  `CAP_DAC_OVERRIDE` не может в него писать, откуда `sqlite3.OperationalError:
  attempt to write a readonly database`.

Поэтому оставлена исходная конфигурация: только `security_opt: label:disable`
(SELinux-метка), без `user` и без `cap_drop`.
