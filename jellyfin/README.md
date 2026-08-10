# Jellyfin

Jellyfin хранит конфигурацию в `/storage/apps/jellyfin`, читает общую медиатеку
из `/storage/media` и доступен через Traefik по адресу
`https://jellyfin.example.net/`. Порты контейнера на хосте не
публикуются; локальный DNS уже направляет все поддомены зоны на Traefik.

Образ закреплён на мажорной версии `jellyfin/jellyfin:10`: обновления внутри
линейки 10 устанавливаются при явном `docker compose pull`, а переход на
следующую мажорную версию требует изменения Compose-файла.

## Запуск

На сервере создать локальный файл окружения и постоянные каталоги:

```sh
cd /home/artlab/projects/homelab/jellyfin
cp .env.example .env
chmod 600 .env
mkdir -p /storage/apps/jellyfin/config /storage/apps/jellyfin/cache /storage/media
docker compose config --quiet
docker compose pull
docker compose up -d
```

При существующей установке каталоги `/config` и `/cache` сохраняются, поэтому
учётные записи, библиотеки и метаданные переживают пересоздание контейнера.
Медиатека подключена только для чтения. Копировать фильмы, сериалы и музыку
нужно на хост в подкаталоги `/storage/media`; в Jellyfin они видны внутри
`/media`.

## Аппаратное декодирование

Compose передаёт AMD Radeon 680M как `/dev/dri/renderD128` и добавляет процесс в
группу `render`. Если числовой GID этой группы изменится, обновить
`JELLYFIN_RENDER_GROUP_ID` в `.env` по результату `getent group render`.

В панели администратора Jellyfin аппаратное ускорение включается отдельно:
`Playback` → `Transcoding` → `VA-API`, устройство
`/dev/dri/renderD128`. Перед включением проверить воспроизведение и логи на
конкретном кодеке; программное транскодирование остаётся безопасным вариантом
по умолчанию.

## Проверка

```sh
docker compose ps
docker exec jellyfin curl -fsS http://127.0.0.1:8096/health
curl --resolve jellyfin.example.net:443:192.0.2.10 \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://jellyfin.example.net/
```
