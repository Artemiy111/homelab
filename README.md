# Домашний сервер

Конфигурация домашнего сервера Fedora 44 по адресу `192.0.2.10`
(`ssh homelab`). Сейчас используется Docker Compose; в будущем планируется
переход на k3s.

## Системные сервисы

| Сервис | Назначение | Адрес в локальной сети |
| --- | --- | --- |
| Traefik | Обратный прокси и обнаружение сервисов | `https://traefik.example.net/dashboard/` |
| Homepage | Стартовая страница сервисов homelab | `https://home.example.net/` |
| Pi-hole | Локальный DNS и блокировка рекламы | `https://pihole.example.net/admin/` |
| Uptime Kuma | Мониторинг доступности | `https://uptime.example.net/` |
| Beszel | Метрики хоста и Docker-контейнеров | `https://beszel.example.net/` |
| WUD | Отслеживание обновлений Docker images | `https://wud.example.net/` |
| Cup | Лёгкая независимая проверка обновлений Docker images | `https://cup.example.net/` |
| 3x-ui | Управление личным Xray-прокси | `https://xui.example.net/<секретный-путь>/` |
| Immich | Фото- и видеотека | `https://immich.example.net/` |
| Jellyfin | Домашний медиасервер | `https://jellyfin.example.net/` |
| Jitsi Meet | Приватные видеоконференции | `https://meet.example.net/` |
| Nextcloud | Файлы, синхронизация, календарь и контакты | `https://nextcloud.example.net/` |
| Gitea | Приватный Git-сервис | `https://gitea.example.net/` |
| Pocket ID | Passkey-аутентификация и OpenID Connect | `https://id.example.net/` |
| Dawarich | История местоположений и карта перемещений | `https://dawarich.example.net/` |
| Stirling PDF | Операции с PDF и OCR | `https://pdf.example.net/` |
| Restic | Зашифрованные локальные снимки | Только CLI |
| Tailscale | Удалённый доступ и маршрут в домашнюю сеть | Tailnet |

Сервисы работают только в локальной сети и используют HTTPS. Не следует
пробрасывать на роутере порты 53, 80 и 443. Для локальных клиентов Pi-hole
разрешает зону <dns-provider> и все её поддомены в `192.0.2.10`. Публичный DNS,
динамическое обновление адреса и публикация сервисов не требуются: удалённый
доступ проходит через Tailscale.

Удалённый доступ без публикации портов в интернете настраивается через
[Tailscale](tailscale/README.md).

## Порядок запуска

1. Установить Docker Engine и плагин Compose.
2. Оставить SELinux в режиме enforcing, а firewalld — включённым.
3. Создать общую сеть прокси: `docker network create traefiknet`.
4. В каталоге каждого сервиса скопировать `.env.example` в `.env` и заменить
   значения-заглушки.
5. Запустить `traefik`, затем `home`, `pihole`, `uptime-kuma`, `beszel`, `3x-ui`,
   `nextcloud`, `jellyfin`, `gitea`, `pocket-id`, `dawarich`, `pdf` и
   `image-updates`.
6. Настроить DHCP-сервер роутера так, чтобы он выдавал `192.0.2.10` как DNS.
7. Инициализировать Restic, создать копию и проверить восстановление.

Первичную подготовку каталогов, сети и локальных `.env` можно выполнить командой:

```sh
bash scripts/bootstrap-platform.sh
```

Скрипт не перезаписывает существующие `.env` и сохраняет сгенерированные пароли
только на сервере с правами доступа `0600`.

Каждый сервис управляется из своего каталога:

```sh
cd traefik
docker compose config
docker compose up -d
```

Секреты находятся в игнорируемом файле `.env` рядом с Compose-файлом. В Git
добавляются только файлы `.env.example`.

Старые и экспериментальные каталоги приложений сохранены для последующего
разбора. В частности, `caddy/` не входит в активный стек и не должен запускаться
одновременно с Traefik: оба сервиса публикуют порты 80 и 443. `wg-easy/` также
пока не разворачивается.

## Пакеты хоста

- `@virtualization`
- `nvim`
- `fd`
- `fastfetch`
- `htop`
- `btop`

Будущая установка k3s: [краткое руководство](https://docs.k3s.io/quick-start).

Установка Lazygit: [инструкция для Fedora](https://github.com/jesseduffield/lazygit#fedora-and-centos-stream).

```sh
sudo dnf copr enable dejan/lazygit
sudo dnf install lazygit
```
