workspace {
    name "HomeLab"
    description "Архитектура домашнего сервера (Docker Compose, Fedora 44, 192.0.2.10)"

    model {

        owner = person "Домохозяин" "Пользователь, обращается к сервисам по HTTPS из LAN или через Tailscale"

        letsencrypt = softwareSystem "Let's Encrypt" "Выдаёт TLS-сертификаты для *.example.com (ACME DNS-01)" {
            tags "external"
        }

        dns_provider = softwareSystem "<dns-provider>" "Публичная DNS-зона example.com; TSIG-ключ для DNS-01 challenge" {
            tags "external"
        }

        cloudflare = softwareSystem "Cloudflare DNS" "Публичные резолверы 1.1.1.1 / 1.0.0.1 — апстримы Technitium DNS" {
            tags "external"
        }

        tailscaleSaaS = softwareSystem "Tailscale SaaS" "Координация tailnet и адресация устройств" {
            tags "external"
        }

        dockerEngine = softwareSystem "Docker Engine" "Демон Docker на хосте, доступ через unix-сокет" {
            tags "external"
        }

        persistentStorage = softwareSystem "Persistent storage" "$APPS_STORAGE_PATH — данные контейнеров на диске хоста (переменная из корневого config.env)" {
            tags "external"
        }

        mediaLibrary = softwareSystem "Media library" "/storage/media — общая медиатека на хосте" {
            tags "external"
        }

        resticRepo = softwareSystem "Restic repository" "/storage/backups/restic — зашифрованные локальные снимки" {
            tags "external"
        }

        spotify = softwareSystem "Spotify" "Метаданные треков для импорта spotDL" {
            tags "external"
        }

        youtube = softwareSystem "YouTube Music" "Источник аудио для импорта spotDL" {
            tags "external"
        }

        group "Инфраструктура" {

            traefik = softwareSystem "Traefik" "Обратный прокси и discovery сервисов (traefik:v3.7); HTTPS, websecure + wildcard-сертификат" {
                tags "infra"
            }

            technitium = softwareSystem "Technitium DNS" "Полноценный DNS-сервер; слушает :53 (DNS), веб-панель через Traefik, рекурсия + блокировка" {
                tags "infra"
            }

            homepage = softwareSystem "Homepage" "Стартовая страница со ссылками на все сервисы (home.example.com)" {
                tags "infra"
            }

            tailscale = softwareSystem "Tailscale (host)" "Системный клиент tailnet; удалённый SSH и маршрут 192.0.2.10/24" {
                tags "infra"
            }
        }

        group "Мониторинг и обновления" {

            uptime = softwareSystem "Uptime Kuma" "Мониторинг доступности (kuma.example.com)" {
                tags "monitoring"
            }

            gatus = softwareSystem "Gatus" "Декларативный статус-пейдж и health-чеки (uptime.example.com)" {
                tags "monitoring"
            }

            beszel = softwareSystem "Beszel" "Метрики хоста и Docker-контейнеров (beszel.example.com)" {
                tags "monitoring"
            }

            wud = softwareSystem "WUD" "Отслеживание обновлений Docker-образов (wud.example.com, basicauth)" {
                tags "monitoring"
            }

            cup = softwareSystem "Cup" "Независимая проверка обновлений образов (cup.example.com, basicauth)" {
                tags "monitoring"
            }

            arcane = softwareSystem "Arcane" "Управление Docker: контейнеры, образы, сети, тома (arcane.example.com)" {
                tags "monitoring"
            }

            arcaneproxy = softwareSystem "Docker Socket Proxy (Arcane)" "Ограниченный прокси docker.sock для Arcane (ro mount, POST включён)" {
                tags "monitoring"
            }

            socketproxy = softwareSystem "Docker Socket Proxy" "Ограниченный прокси docker.sock (read-only, без POST)" {
                tags "monitoring"
            }

            restic = softwareSystem "Restic" "CLI-бэкапы $APPS_STORAGE_PATH и конфига в зашифрованный локальный репозиторий" {
                tags "monitoring"
            }
        }

        group "Идентификация и доступ" {

            authentik = softwareSystem "Authentik" "Identity provider и SSO (auth.example.com)" {
                tags "idm"
            }

            xui = softwareSystem "3x-ui (Xray)" "Панель управления личным Xray-прокси; inbound :8443 (TCP/UDP)" {
                tags "idm"
            }
        }

        group "Файлы, код и разработка" {

            nextcloud = softwareSystem "Nextcloud" "Файлы, синхронизация, календарь и контакты (nextcloud.example.com)" {
                tags "files"
            }

            forgejo = softwareSystem "Forgejo" "Приватный Git-сервис: web + SSH (:2222) (forgejo.example.com)" {
                tags "files"
            }

            codeserver = softwareSystem "code-server" "VS Code в браузере (code.example.com)" {
                tags "files"
            }
        }

        group "Медиа и развлечения" {

            immich = softwareSystem "Immich" "Фото- и видеотека (immich.example.com)" {
                tags "media"
            }

            jellyfin = softwareSystem "Jellyfin" "Домашний медиасервер с аппаратным декодированием VA-API (jellyfin.example.com)" {
                tags "media"
            }

            navidrome = softwareSystem "Navidrome" "Музыкальный сервер (music.example.com)" {
                tags "media"
            }

            jitsi = softwareSystem "Jitsi Meet" "Приватные видеоконференции (meet.example.com); медиа по UDP :10000" {
                tags "media"
            }

            spotdl = softwareSystem "spotDL" "По требованию: импорт музыки из Spotify/YouTube в /storage/media/music" {
                tags "media"
            }
        }

        group "Приложения" {

            dawarich = softwareSystem "Dawarich" "История местоположений и карта перемещений (dawarich.example.com)" {
                tags "apps"
            }

            pdf = softwareSystem "Stirling PDF" "Операции с PDF и OCR (pdf.example.com)" {
                tags "apps"
            }

            homeassistant = softwareSystem "Home Assistant" "Домашняя автоматизация; host-сеть, доступ только из LAN (ha.example.com)" {
                tags "apps"
            }

            lute = softwareSystem "Lute" "Приложение для чтения и изучения языков (lute.example.com)" {
                tags "apps"
            }

            mermaid = softwareSystem "Mermaid Live Editor" "Редактор Mermaid-диаграмм в браузере (mermaid.example.com)" {
                tags "apps"
            }

            structurizr = softwareSystem "Structurizr" "Инструмент C4-диаграмм, этот воркспейс (structurizr.example.com)" {
                tags "apps"
            }

            localai = softwareSystem "LocalAI" "Локальный OpenAI-совместимый API инференса (localai.example.com)" {
                tags "apps"
            }

            sure = softwareSystem "Sure" "Семейное Rails-приложение (we-promise/sure); доступ через Traefik (sure.example.com)" {
                tags "apps"
            }
        }

        owner -> traefik "HTTPS-запросы (LAN / Tailscale)" "HTTPS"
        owner -> forgejo "Git over SSH (:2222)" "SSH"
        owner -> xui "Xray-клиенты (TCP/UDP :8443)" "TCP/UDP"
        owner -> jitsi "медиа-потоки (UDP :10000)" "UDP"
        owner -> sure "HTTPS (sure.example.com)" "HTTPS"
        owner -> tailscale "удалённый доступ к сервисам извне LAN" "Tailscale"

        traefik -> homepage "маршрутизирует Host(home.*)" "HTTPS" {
            tags "http"
        }
        traefik -> technitium "маршрутизирует Host(dns.*)" "HTTPS" {
            tags "http"
        }
        traefik -> uptime "маршрутизирует Host(kuma.*)" "HTTPS" {
            tags "http"
        }
        traefik -> gatus "маршрутизирует Host(uptime.*)" "HTTPS" {
            tags "http"
        }
        traefik -> beszel "маршрутизирует Host(beszel.*)" "HTTPS" {
            tags "http"
        }
        traefik -> wud "маршрутизирует Host(wud.*)" "HTTPS" {
            tags "http"
        }
        traefik -> cup "маршрутизирует Host(cup.*)" "HTTPS" {
            tags "http"
        }
        traefik -> arcane "маршрутизирует Host(arcane.*)" "HTTPS" {
            tags "http"
        }
        traefik -> authentik "маршрутизирует Host(auth.*)" "HTTPS" {
            tags "http"
        }
        traefik -> xui "маршрутизирует Host(xui.*)" "HTTPS" {
            tags "http"
        }
        traefik -> nextcloud "маршрутизирует Host(nextcloud.*)" "HTTPS" {
            tags "http"
        }
        traefik -> forgejo "маршрутизирует Host(forgejo.*)" "HTTPS" {
            tags "http"
        }
        traefik -> codeserver "маршрутизирует Host(code.*)" "HTTPS" {
            tags "http"
        }
        traefik -> immich "маршрутизирует Host(immich.*)" "HTTPS" {
            tags "http"
        }
        traefik -> jellyfin "маршрутизирует Host(jellyfin.*)" "HTTPS" {
            tags "http"
        }
        traefik -> navidrome "маршрутизирует Host(music.*)" "HTTPS" {
            tags "http"
        }
        traefik -> jitsi "маршрутизирует Host(meet.*)" "HTTPS" {
            tags "http"
        }
        traefik -> dawarich "маршрутизирует Host(dawarich.*)" "HTTPS" {
            tags "http"
        }
        traefik -> pdf "маршрутизирует Host(pdf.*)" "HTTPS" {
            tags "http"
        }
        traefik -> homeassistant "маршрутизирует Host(ha.*)" "HTTPS" {
            tags "http"
        }
        traefik -> lute "маршрутизирует Host(lute.*)" "HTTPS" {
            tags "http"
        }
        traefik -> mermaid "маршрутизирует Host(mermaid.*)" "HTTPS" {
            tags "http"
        }
        traefik -> structurizr "маршрутизирует Host(structurizr.*)" "HTTPS" {
            tags "http"
        }
        traefik -> localai "маршрутизирует Host(localai.*)" "HTTPS" {
            tags "http"
        }

        traefik -> letsencrypt "получает сертификаты (ACME DNS-01)" "ACME DNS-01"
        letsencrypt -> dns_provider "публикует TXT-записи _acme-challenge через TSIG" "DNS (TSIG)"
        technitium -> cloudflare "рекурсивные DNS-запросы" "DNS"
        tailscale -> technitium "DNS для зоны example.com через tailnet" "DNS"
        tailscale -> tailscaleSaaS "координация tailnet (WireGuard)" "WireGuard"

        dockerEngine -> traefik "docker.sock (ro) — discovery сервисов" "docker.sock (ro)"
        dockerEngine -> beszel "docker.sock (ro) — метрики контейнеров" "docker.sock (ro)"
        dockerEngine -> socketproxy "docker.sock (ro, без POST)" "docker.sock (ro)"
        dockerEngine -> arcaneproxy "docker.sock (ro, POST включён)" "docker.sock (ro)"
        socketproxy -> wud "список образов и тегов (TCP :2375)" "TCP :2375"
        socketproxy -> cup "список образов и тегов (TCP :2375)" "TCP :2375"
        arcaneproxy -> arcane "API Docker (TCP :2375)" "TCP :2375"

        jellyfin -> mediaLibrary "читает /storage/media" "host bind mount"
        navidrome -> mediaLibrary "читает /storage/media/music" "host bind mount"
        immich -> mediaLibrary "читает библиотеки /storage/media" "host bind mount"
        spotdl -> mediaLibrary "пишет в /storage/media/music" "host bind mount"
        spotdl -> spotify "запрашивает метаданные треков" "Web API"
        spotdl -> youtube "скачивает аудио" "yt-dlp"

        restic -> persistentStorage "бэкапит $APPS_STORAGE_PATH и конфиг репозитория" "host bind mount"
        restic -> resticRepo "создаёт шифрованные снимки" "Restic"
    }

    views {

        systemLandscape "AllServices-001" {
            title "Все сервисы домашнего сервера"
            include *
            exclude relationship.tag==http
            autoLayout tb 350 150
        }

        systemLandscape "Infra-001" "Инфраструктура" {
            include element.tag==infra dockerEngine letsencrypt dns_provider cloudflare
            autoLayout tb 250 100
        }

        systemLandscape "Monitoring-001" "Мониторинг и обновления" {
            include element.tag==monitoring dockerEngine persistentStorage resticRepo
            autoLayout tb 250 100
        }

        systemLandscape "Idm-001" "Идентификация и доступ" {
            include element.tag==idm traefik owner
            autoLayout tb 250 100
        }

        systemLandscape "Files-001" "Файлы, код и разработка" {
            include element.tag==files traefik owner
            autoLayout tb 250 100
        }

        systemLandscape "Media-001" "Медиа и развлечения" {
            include element.tag==media traefik mediaLibrary spotify youtube owner
            autoLayout tb 250 100
        }

        systemLandscape "Apps-001" "Приложения" {
            include element.tag==apps traefik owner
            autoLayout tb 250 100
        }

        systemContext traefik "Traefik-001" {
            title "Traefik — обратный прокси"
            include *
            autoLayout tb 350 150
        }

        styles {
            element "Person" {
                shape Person
            }
            element "System" {
                shape RoundedBox
                fontSize 11
            }
            element "external" {
                background #7f8c8d
                color #ffffff
                stroke #566573
            }
            element "infra" {
                background #1565c0
                color #ffffff
            }
            element "monitoring" {
                background #00838f
                color #ffffff
            }
            element "idm" {
                background #6a1b9a
                color #ffffff
            }
            element "files" {
                background #2e7d32
                color #ffffff
            }
            element "media" {
                background #c62828
                color #ffffff
            }
            element "apps" {
                background #ef6c00
                color #ffffff
            }
            element "Group" {
                background #f7f9fb
                color #37474f
                stroke #cfd8dc
            }
            relationship "http" {
                color #1565c0
                dashed true
            }
        }
    }

    configuration {
        scope landscape
    }
}
