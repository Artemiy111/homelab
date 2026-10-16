# spotDL: эксплуатация

## Подготовка и импорт

На узле один раз создайте доступные для записи каталоги:

```sh
ssh homelab 'mkdir -p ${APPS_STORAGE_PATH:-/storage/apps}/spotdl/config /storage/media/music'
```

Compose запускается с контроллера (macOS) против Docker узла по SSH:

```sh
cd clusters/casa/apps/spotdl
DOCKER_HOST=ssh://homelab docker compose --profile tools config --quiet
```

Загрузите разрешённый трек, альбом или плейлист по URL:

```sh
DOCKER_HOST=ssh://homelab docker compose --profile tools run --rm spotdl download 'SPOTIFY_URL'
```

Для плейлиста, который нужно обновлять в дальнейшем, сохраните состояние и
затем синхронизируйте его:

```sh
DOCKER_HOST=ssh://homelab docker compose --profile tools run --rm spotdl save 'SPOTIFY_PLAYLIST_URL' --save-file playlist.spotdl
DOCKER_HOST=ssh://homelab docker compose --profile tools run --rm spotdl sync playlist.spotdl
```

## Обновление

При изменениях на внешних сервисах spotDL может потребовать обновления: сначала
обновите закреплённый тег образа в `compose.yaml`, затем проверьте
Compose-конфигурацию до развёртывания.
