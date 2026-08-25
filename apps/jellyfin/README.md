# Jellyfin

URL: `https://jellyfin.example.com/`
Читает общую медиатеку из `/storage/media`.

## Запуск

```sh
bash ./init.sh
install -d /storage/media
docker compose pull
docker compose up -d
docker compose ps
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
curl --resolve jellyfin.example.com:443:192.0.2.10 \
  -o /dev/null -sS -w '%{http_code}\n' \
  https://jellyfin.example.com/
```
