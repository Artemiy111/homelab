# spotDL: эксплуатация

## Подготовка и импорт

На сервере один раз создайте доступные для записи каталоги:

```sh
mkdir -p ${APPS_STORAGE_PATH:-/storage/apps}/spotdl/config /storage/media/music
cd /home/artlab/projects/homelab/spotdl
docker compose --profile tools config --quiet
```

Загрузите разрешённый трек, альбом или плейлист по URL:

```sh
docker compose --profile tools run --rm spotdl download 'SPOTIFY_URL'
```

Для плейлиста, который нужно обновлять в дальнейшем, сохраните состояние и
затем синхронизируйте его:

```sh
docker compose --profile tools run --rm spotdl save 'SPOTIFY_PLAYLIST_URL' --save-file playlist.spotdl
docker compose --profile tools run --rm spotdl sync playlist.spotdl
```

## Обновление

При изменениях на внешних сервисах spotDL может потребовать обновления: сначала
обновите закреплённый тег образа в `compose.yaml`, затем проверьте
Compose-конфигурацию до развёртывания.
