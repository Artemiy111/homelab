# Dawarich

Dawarich хранит и визуализирует историю местоположений. Веб-интерфейс доступен
через Traefik по адресу `https://dawarich.example.net/`; порты
приложения, PostgreSQL и Redis на хост не публикуются. Локальный wildcard DNS уже
направляет этот адрес на Traefik.

Образ Dawarich закреплён на версии `1.11.0`: проект активно развивается и не
рекомендует автоматические обновления. Постоянные данные находятся в
`/storage/apps/dawarich` и входят в общий Restic snapshot.

## Первый запуск

Общий bootstrap создаёт каталоги и `.env`, генерирует независимые секреты
PostgreSQL и Rails и сохраняет их только на сервере с правами `0600`:

```sh
cd /home/artlab/projects/homelab
bash scripts/bootstrap-platform.sh
cd dawarich
docker compose config --quiet
docker compose pull
docker compose up -d
docker compose ps
```

После запуска войдите с начальными реквизитами Dawarich
`demo@dawarich.app` / `safepassword` и сразу смените пароль в настройках
аккаунта.

## Проверка

```sh
docker compose ps
docker compose exec app wget --header='X-Forwarded-Proto: https' -qO- \
  http://127.0.0.1:3000/api/v1/health
curl --resolve dawarich.example.net:443:192.0.2.10 \
  -fsS https://dawarich.example.net/api/v1/health
```

Health endpoint должен вернуть JSON со `"status":"ok"`.

## Резервное копирование

Для согласованной копии остановите процессы, меняющие данные, создайте дамп
PostgreSQL, затем запустите общий Restic backup:

```sh
cd /home/artlab/projects/homelab/dawarich
docker compose stop app sidekiq
docker compose --profile tools run --rm backup-db
cd ../restic
docker compose run --rm backup
cd ../dawarich
docker compose start app sidekiq
```

Дамп сохраняется в `/storage/apps/dawarich/backups/dawarich.dump`. Restic
repository находится на том же физическом диске и не защищает от его поломки
или потери. Исходные файлы импорта не следует удалять после загрузки в Dawarich.

## Обновление

Перед обновлением создайте согласованный backup, прочитайте release notes и
измените `DAWARICH_VERSION` одновременно в `.env.example` и серверном `.env`.
Затем выполните:

```sh
docker compose pull
docker compose up -d
docker compose ps
```
