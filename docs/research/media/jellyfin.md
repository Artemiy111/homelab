# Jellyfin в Docker Compose

Дата проверки: 2026-08-10.

## Вывод

Для этого репозитория следует использовать официальный образ
`jellyfin/jellyfin:10`. Тег `10` фиксирует мажорную версию и при повторном
развёртывании получает последние исправления ветки 10.x. На дату проверки
последний стабильный выпуск —
[10.11.11](https://github.com/jellyfin/jellyfin/releases/tag/v10.11.11).
Опубликованный официальный
[Docker Hub tag `10`](https://hub.docker.com/r/jellyfin/jellyfin/tags?name=10)
соответствует этой ветке.

Предпочтительный адрес — отдельный поддомен
`https://jellyfin.example.com/`, а не URL-путь вида `/jellyfin`.
Traefik должен завершать TLS и проксировать HTTP на порт 8096 контейнера через
общую сеть `traefiknet`. Встроенный HTTPS Jellyfin для такой схемы не нужен.

## Образ и стратегия версий

Jellyfin публикует официальный образ как `jellyfin/jellyfin` в Docker Hub и как
`ghcr.io/jellyfin/jellyfin` в GitHub Container Registry. Официальная
[документация контейнера](https://jellyfin.org/docs/general/installation/container/)
описывает семантику тегов:

- `latest` переходит через major и minor релизы;
- `X`, например `10`, остаётся на major и получает последний `10.Y.Z`;
- `X.Y` остаётся на minor;
- `X.Y.Z` фиксирует конкретный релиз;
- полный тег с датой фиксирует также конкретную сборку упаковки.

Поэтому требованию «зафиксировать мажорную версию» точно соответствует
`jellyfin/jellyfin:10`. Использование `latest` не соответствует этому
требованию, а фиксация `10.11.11` потребовала бы ручного изменения Compose для
каждого patch-релиза, включая исправления безопасности.

Официальные образы основаны на Debian, собираются непосредственно из исходного
кода Jellyfin и доступны для нескольких архитектур. Исходный
[Dockerfile образа](https://github.com/jellyfin/jellyfin-packaging/blob/master/docker/Dockerfile)
находится в официальном репозитории упаковки.

## Постоянные данные и медиа

Официальный Compose-пример требует постоянные mounts:

- `/config` — конфигурация, база данных и логи;
- `/cache` — кэш и данные транскодирования;
- один или несколько произвольных путей с медиатекой, например `/media`.

Медиатеку можно подключить read-only, если Jellyfin не должен изменять файлы
рядом с медиа. Дополнительно можно read-only подключить системные шрифты в
`/usr/local/share/fonts/custom` для вжигания субтитров. Все эти mount points и
Compose-пример приведены в официальной
[инструкции по контейнеру](https://jellyfin.org/docs/general/installation/container/?method=docker-compose).

## Сеть и URL

Порты Jellyfin описаны в официальной
[сетевой документации](https://jellyfin.org/docs/general/post-install/networking/):

- `8096/tcp` — HTTP и web UI;
- `8920/tcp` — встроенный HTTPS, по умолчанию выключен;
- `7359/udp` — обнаружение клиентами в локальной сети.

Для обычного web-доступа достаточно bridge network. Официальная инструкция
указывает, что host network необязательна и нужна для DLNA. В схеме этого
репозитория контейнеру достаточно состоять в `traefiknet`; публиковать 8096 на
host не требуется, поскольку Traefik обращается к контейнеру напрямую. Порт
`7359/udp` имеет смысл публиковать только если нужно локальное автообнаружение.
DLNA потребует отдельного решения с host networking и не должен включаться
автоматически вместе с обычной Traefik-схемой.

Для внешнего адреса следует задать
`JELLYFIN_PublishedServerUrl=https://jellyfin.example.com`: официальная
Compose-инструкция описывает эту переменную как альтернативный адрес для
автообнаружения.

Официальная документация рекомендует завершать HTTPS на reverse proxy. Jellyfin
требует WebSocket-проксирование, а адрес или подсеть Traefik нужно добавить в
**Known Proxies**, чтобы сервер доверял `X-Forwarded-For`, `X-Forwarded-Proto` и
`X-Forwarded-Host`; подробности находятся в
[руководстве по reverse proxy](https://jellyfin.org/docs/general/post-install/networking/reverse-proxy/).

Base URL следует оставить пустым (`/`) и использовать поддомен. Путь вида
`/jellyfin` поддерживается, но официальная документация предупреждает о
несовместимости с HDHomeRun, DLNA plugin, Sonarr, Radarr и MrMC, а клиенты должны
явно включать Base URL в адрес сервера. Изменение Base URL требует перезапуска.

## Healthcheck

Отдельный healthcheck добавлять необязательно: официальный образ содержит
Docker `HEALTHCHECK`, который каждые 30 секунд выполняет запрос к
`http://localhost:8096/health`, с timeout 30 секунд, start period 10 секунд и
тремя повторами. Это видно непосредственно в официальном
[Dockerfile релиза 10.11.11](https://github.com/jellyfin/jellyfin-packaging/blob/v10.11.11-202606061137/docker/Dockerfile).
Compose наследует healthcheck образа, если его явно не переопределить или не
отключить.

При host networking официальная Compose-инструкция отмечает, что для
прохождения встроенного healthcheck может понадобиться mapping
`host.docker.internal:host-gateway`. Для выбранной bridge-схемы это не нужно.

## Аппаратное транскодирование

Включать доступ к GPU следует только после проверки конкретного устройства на
сервере. Официальный образ уже включает `jellyfin-ffmpeg` и необходимые
userspace-компоненты для поддерживаемых сценариев, но контейнеру всё равно нужен
доступ к устройствам и корректные группы:

- Intel/AMD на Linux: обычно передать `/dev/dri` и добавить GID host-группы
  `render` (иногда `video` или `input`); для Intel предпочтителен QSV на
  поддерживаемых поколениях, для AMD — VA-API;
- NVIDIA: установить proprietary driver и NVIDIA Container Toolkit на host;
  официальный образ не содержит proprietary driver, но уже задаёт необходимые
  NVIDIA environment variables.

Точные шаги зависят от GPU и приведены в официальных руководствах для
[Intel](https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/intel/),
[AMD](https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/amd/)
и
[NVIDIA](https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/nvidia/).
На Fedora с SELinux дополнительно нужно проверить доступ контейнера к DRI;
общая инструкция контейнера отдельно указывает на SELinux-ограничения для
render devices.

## Минимальная форма Compose для репозитория

Это ориентир для реализации, не готовая конфигурация с выбранными host paths:

```yaml
services:
  jellyfin:
    image: jellyfin/jellyfin:10
    restart: unless-stopped
    environment:
      JELLYFIN_PublishedServerUrl: https://jellyfin.example.com
    volumes:
      - <config>:/config:Z
      - <cache>:/cache:Z
      - <media>:/media:z,ro
    networks:
      - traefiknet
    labels:
      - traefik.enable=true
      - traefik.http.routers.jellyfin.rule=Host(`jellyfin.example.com`)
      - traefik.http.routers.jellyfin.entrypoints=websecure
      - traefik.http.services.jellyfin.loadbalancer.server.port=8096
      - traefik.docker.network=traefiknet

networks:
  traefiknet:
    external: true
```

Путь `/config` необходимо включить в резервные копии перед обновлениями: в
[release notes 10.11.11](https://github.com/jellyfin/jellyfin/releases/tag/v10.11.11)
Jellyfin, как и для других выпусков, рекомендует сделать полную резервную копию
перед обновлением.
