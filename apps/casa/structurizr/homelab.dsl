workspace {
    name "HomeLab"
    description "Архитектура домашнего сервера (Fedora 44, <node1-ip>)"

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

        persistentStorage = softwareSystem "Persistent storage" "$APPS_STORAGE_PATH — данные контейнеров на диске хоста" {
            tags "external"
        }

        mediaLibrary = softwareSystem "Media library" "/storage/media — общая медиатека на хосте" {
            tags "external"
        }

        spotify = softwareSystem "Spotify" "Метаданные треков для импорта spotDL" {
            tags "external"
        }

        youtube = softwareSystem "YouTube Music" "Источник аудио для импорта spotDL" {
            tags "external"
        }

        group "Инфраструктура" {

            traefik = softwareSystem "Traefik" "Обратный прокси и discovery сервисов (traefik:v3.7); Gateway API на :80/:443, HTTPRoute + wildcard-сертификат" {
                tags "infra"
            }

            technitium = softwareSystem "Technitium DNS" "Полноценный DNS-сервер; слушает :53 (DNS), веб-панель через Traefik, рекурсия + блокировка" {
                tags "infra"
            }

            homepage = softwareSystem "Homepage" "Стартовая страница со ссылками на все сервисы (home.example.com)" {
                tags "infra"
            }

            tailscale = softwareSystem "Tailscale (host)" "Системный клиент tailnet; удалённый SSH и маршрут <node1-lan-cidr>" {
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

            socketproxy = softwareSystem "Docker Socket Proxy" "Ограниченный прокси docker.sock (read-only, без POST)" {
                tags "monitoring"
            }

            victoriametrics = softwareSystem "VictoriaMetrics" "Долговременное хранилище метрик (vm.example.com)" {
                tags "monitoring"
            }

            netdata = softwareSystem "Netdata" "Живая диагностика хостов и контейнеров (netdata.example.com)" {
                tags "monitoring"
            }

            headlamp = softwareSystem "Headlamp" "Веб-UI для Kubernetes (headlamp.example.com)" {
                tags "monitoring"
            }

            radar = softwareSystem "Radar" "Сводка состояния сервисов и инцидентов (radar.example.com)" {
                tags "monitoring"
            }

            glitchtip = softwareSystem "GlitchTip" "Сбор ошибок фронтендов (glitchtip.example.com)" {
                tags "monitoring"
            }

            postgres = softwareSystem "PostgreSQL" "Внешний инстанс для утилит и отчётов (postgres.example.com)" {
                tags "monitoring"
            }
        }

        group "Идентификация и доступ" {

            zitadel = softwareSystem "Zitadel" "Основной OIDC-провайдер (auth.example.com)" {
                tags "idm"
            }

            oauth2proxy = softwareSystem "oauth2-proxy" "Forward auth перед Traefik: проверяет сессию с Zitadel (oauth.example.com)" {
                tags "idm"
            }

            vault = softwareSystem "Vault" "Хранилище секретов; выдаёт их через Secret Store CSI и Vault Secrets Operator" {
                tags "idm"
            }

            infisical = softwareSystem "Infisical" "Веб-интерфейс к секретам (infisical.example.com)" {
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

            seafile = softwareSystem "Seafile" "Синхронизация файлов с OnlyOffice (seafile.example.com)" {
                tags "files"
            }

            onlyoffice = softwareSystem "OnlyOffice" "Редактор документов для Seafile (onlyoffice.example.com)" {
                tags "files"
            }

            gitlab = softwareSystem "GitLab" "Второй Git-сервис; выключен (0 реплик) (gitlab.example.com)" {
                tags "files"
            }
        }

        group "Внутренние зеркала" {

            rustfs = softwareSystem "RustFS" "S3-совместимое хранилище артефактов (s3.example.com)" {
                tags "mirror"
            }

            ats = softwareSystem "ATS" "HTTP-кэш для релизов GitHub и бинарей CI" {
                tags "mirror"
            }

            athens = softwareSystem "Athens" "Go-прокси для модулей (goproxy.example.com)" {
                tags "mirror"
            }

            verdaccio = softwareSystem "Verdaccio" "npm-прокси (verdaccio.example.com)" {
                tags "mirror"
            }

            zot = softwareSystem "Zot" "OCI-реестр образов (zot.example.com)" {
                tags "mirror"
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

            element = softwareSystem "Element" "Клиент Matrix; собственный homeserver (element.example.com)" {
                tags "apps"
            }

            talkhpb = softwareSystem "Talk HPB" "Сигналинг Matrix (talk-signaling.example.com)" {
                tags "apps"
            }

            mailserver = softwareSystem "Mailserver" "Почта: SMTP/IMAP и веб-почта (mail.example.com)" {
                tags "apps"
            }

            paperless = softwareSystem "Paperless-ngx" "Сканирование и архив документов (paperless.example.com)" {
                tags "apps"
            }

            openwebui = softwareSystem "Open WebUI" "Веб-интерфейс к локальным LLM (ai.example.com)" {
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
        traefik -> zitadel "аутентифицирует через OIDC" "OIDC"
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
        traefik -> seafile "маршрутизирует Host(seafile.*)" "HTTPS" {
            tags "http"
        }
        traefik -> onlyoffice "маршрутизирует Host(onlyoffice.*)" "HTTPS" {
            tags "http"
        }
        traefik -> gitlab "маршрутизирует Host(gitlab.*)" "HTTPS" {
            tags "http"
        }
        traefik -> victoriametrics "маршрутизирует Host(vm.*)" "HTTPS" {
            tags "http"
        }
        traefik -> netdata "маршрутизирует Host(netdata.*)" "HTTPS" {
            tags "http"
        }
        traefik -> headlamp "маршрутизирует Host(headlamp.*)" "HTTPS" {
            tags "http"
        }
        traefik -> radar "маршрутизирует Host(radar.*)" "HTTPS" {
            tags "http"
        }
        traefik -> glitchtip "маршрутизирует Host(glitchtip.*)" "HTTPS" {
            tags "http"
        }
        traefik -> postgres "маршрутизирует Host(postgres.*)" "HTTPS" {
            tags "http"
        }
        traefik -> infisical "маршрутизирует Host(infisical.*)" "HTTPS" {
            tags "http"
        }
        traefik -> oauth2proxy "маршрутизирует Host(oauth.*)" "HTTPS" {
            tags "http"
        }
        traefik -> element "маршрутизирует Host(element.*)" "HTTPS" {
            tags "http"
        }
        traefik -> talkhpb "маршрутизирует Host(talk-signaling.*)" "HTTPS" {
            tags "http"
        }
        traefik -> mailserver "маршрутизирует Host(mail.*)" "HTTPS" {
            tags "http"
        }
        traefik -> paperless "маршрутизирует Host(paperless.*)" "HTTPS" {
            tags "http"
        }
        traefik -> openwebui "маршрутизирует Host(ai.*)" "HTTPS" {
            tags "http"
        }

        oauth2proxy -> zitadel "проверяет сессию OIDC" "OIDC"
        forgejo -> rustfs "CI тянет бинари и образы" "S3"
        forgejo -> ats "CI тянет GitHub-релизы через кэш" "HTTP"
        forgejo -> athens "CI тянет Go-модули" "Go proxy"
        forgejo -> verdaccio "CI тянет npm-пакеты" "npm"
        forgejo -> zot "CI тянет образы" "OCI"

        traefik -> letsencrypt "получает сертификаты (ACME DNS-01)" "ACME DNS-01"
        letsencrypt -> dns_provider "публикует TXT-записи _acme-challenge через TSIG" "DNS (TSIG)"
        technitium -> cloudflare "рекурсивные DNS-запросы" "DNS"
        tailscale -> technitium "DNS для зоны example.com через tailnet" "DNS"
        tailscale -> tailscaleSaaS "координация tailnet (WireGuard)" "WireGuard"

        dockerEngine -> traefik "docker.sock (ro) — discovery сервисов" "docker.sock (ro)"
        dockerEngine -> beszel "docker.sock (ro) — метрики контейнеров" "docker.sock (ro)"
        dockerEngine -> socketproxy "docker.sock (ro, без POST)" "docker.sock (ro)"
        socketproxy -> wud "список образов и тегов (TCP :2375)" "TCP :2375"

        jellyfin -> mediaLibrary "читает /storage/media" "host bind mount"
        navidrome -> mediaLibrary "читает /storage/media/music" "host bind mount"
        immich -> mediaLibrary "читает библиотеки /storage/media" "host bind mount"
        spotdl -> mediaLibrary "пишет в /storage/media/music" "host bind mount"
        seafile -> persistentStorage "хранит данные в $APPS_STORAGE_PATH" "host bind mount"
        vault -> persistentStorage "хранит данные в $APPS_STORAGE_PATH" "host bind mount"
        forgejo -> vault "CI получает секреты (VaultAuth)" "Vault API"
        spotdl -> spotify "запрашивает метаданные треков" "Web API"
        spotdl -> youtube "скачивает аудио" "yt-dlp"
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

        systemLandscape "Mirror-001" "Внутренние зеркала" {
            include element.tag==mirror forgejo
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
            element "mirror" {
                background #455a64
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
