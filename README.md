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
| Forgejo | Приватный Git-сервис | `https://forgejo.example.net/` |
| code-server | VS Code в браузере | `https://code.example.net/` |
| Pocket ID | Passkey-аутентификация и OpenID Connect | `https://pocket-id.example.net/` |
| Authentik | Identity provider и SSO | `https://auth.example.net/` |
| Zitadel | Identity provider и SSO (основной) | `https://id.example.net/` |
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

## Общий домен сервисов

Базовый домен `example.net` задаётся в одном месте и подставляется во
все адреса вида `<sub>.<DOMAIN>`. Источник правды — `scripts/lib/common.sh`
(значение по умолчанию закоммичено). Чтобы переопределить домен без коммита в
Git, скопируйте корневой `.env.example` в `.env` и поправьте `DOMAIN`:

```sh
cp .env.example .env
```

`init.sh` каждого сервиса и `scripts/bootstrap-platform.sh` читают `DOMAIN` и
генерируют конкретные `<SERVICE>_HOST` в локальных `.env` сервисов. Конфиги
Homepage, Gatus и Uptime Kuma подставляют домен через переменные окружения
(`{{HOMEPAGE_VAR_DOMAIN}}`, `${DOMAIN}`, `{{DOMAIN}}` соответственно).
Статические конфиги, не умеющие читать переменные окружения (Traefik static,
dnsmasq, structurizr.properties), генерируются `init.sh` из `.tpl`-шаблонов
через `envsubst` (плейсхолдеры `${DOMAIN}` / `${SERVER_IP}`).
После смены домена заново выполните `bash scripts/bootstrap-platform.sh`.

## IP-адрес сервера

LAN-адрес `192.0.2.10`, к которому привязываются опубликованные порты
(Traefik, Pi-hole, Gitea, 3x-ui, Jitsi) и на который указывают DNS- и
health-проверки (Gatus, Uptime Kuma), задаётся переменной `SERVER_IP`.
По умолчанию `scripts/lib/common.sh` определяет его автоматически как
адрес-источник маршрута по умолчанию (`ip route get 1.1.1.1`). Если нужно
переопределить (например, несколько сетевых интерфейсов), задайте `SERVER_IP`
в корневом `.env` или в переменной окружения.

## Часовой пояс

Часовой пояс контейнеров задаётся переменной `TZ` (по умолчанию
`Asia/Yekaterinburg` в `scripts/lib/common.sh`). `init.sh` подставляет её в
локальные `.env` сервисов, а Compose требует её через `${TZ:?...}`.

## Порядок запуска

1. Установить Docker Engine и плагин Compose.
2. Оставить SELinux в режиме enforcing, а firewalld — включённым.
3. Создать общую сеть прокси: `docker network create traefiknet`.
4. В каталоге каждого сервиса скопировать `.env.example` в `.env` и заменить
   значения-заглушки. Общий домен задаётся один раз — см. раздел
   «Общий домен сервисов».
5. Запустить `traefik`, затем `home`, `pihole`, `uptime-kuma`, `beszel`, `3x-ui`,
   `nextcloud`, `jellyfin`, `forgejo`, `code-server`, `pocket-id`, `authentik`, `dawarich`,
   `pdf` и `image-updates`.
6. Настроить DHCP-сервер роутера так, чтобы он выдавал `192.0.2.10` как DNS.
7. Инициализировать Restic, создать копию и проверить восстановление.

Первичную подготовку каталогов, сети и локальных `.env` можно выполнить командой:

```sh
bash scripts/bootstrap-platform.sh
```

Этот скрипт-оркестратор выполняет общую подготовку (каталог `/storage/media`,
сеть `traefiknet`) и запускает скрипт инициализации каждого сервиса из его
каталога. Отдельный сервис можно подготовить напрямую:

```sh
bash traefik/init.sh
```

Скрипты не перезаписывают существующие `.env` и сохраняют сгенерированные пароли
только на сервере с правами доступа `0600`. Общие функции находятся в
`scripts/lib/common.sh`.

Каждый сервис управляется из своего каталога:

```sh
cd traefik
docker compose config
docker compose up -d
```

Секреты находятся в игнорируемом файле `.env` рядом с Compose-файлом. В Git
добавляются только файлы `.env.example` (включая корневой, задающий `DOMAIN`).

Старые и экспериментальные каталоги приложений сохранены для последующего
разбора. В частности, `caddy/` не входит в активный стек и не должен запускаться
одновременно с Traefik: оба сервиса публикуют порты 80 и 443. `wg-easy/` также
пока не разворачивается.

## Линтинг Compose-файлов

Все `compose.yaml` приводятся к единому порядку полей (смысловая группировка
ключей) через [dclint](https://github.com/zavoloklom/docker-compose-linter) с
конфигом `.dclintrc` в корне. Проверка:

```sh
npx dclint . -r
```

Автоматическое приведение порядка полей:

```sh
npx dclint . -r --fix
python3 scripts/compose-format.py
```

> **Важно:** после линтинга (`dclint --fix`) обязательно запускать ещё и
> `scripts/compose-format.py`. dclint не умеет вставлять пустые строки между
> смысловыми группами ключей, поэтому эту работу делает отдельный скрипт.
> Он идемпотентен и сохраняет комментарии. Запускать оба шага всегда вместе.

Правило `service-keys-order` включает только группировку по смыслу; остальные
стилевые правила отключены в `.dclintrc`, чтобы не менять то, что не просили.
Подробный разбор инструментов — в `docs/research/docker-compose-lint.md`.

## Проверка домена

Базовый домен не должен захардкоживаться в конфигах. Проверка:

```sh
bash scripts/check-domain.sh
```

Скрипт падает, если `example.net` встречается вне разрешённых мест:
источник правды (`scripts/lib/common.sh`), шаблоны (`.env.example`, `.tpl`) и
документация (`.md`, `structurizr/homelab.dsl`).

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
