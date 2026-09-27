locals {
  groups = [
    { key = "infrastructure", title = "Infrastructure", weight = 1, color = "#dc2626" },
    { key = "monitoring", title = "Monitoring", weight = 2, color = "#2563eb" },
    { key = "applications", title = "Applications", weight = 3, color = "#16a34a" },
    { key = "external", title = "External", weight = 4, color = "#9333ea" },
  ]

  monitor_defaults = {
    active                = true
    upside_down           = false
    ignore_tls            = false
    interval              = 60
    retry_interval        = 60
    resend_interval       = 0
    timeout               = 48
    max_retries           = 2
    max_redirects         = 10
    accepted_status_codes = null
    proxy_key             = null
    proxy_id              = null
    keyword               = null
    json_path             = null
    json_path_operator    = null
    expected_value        = null
    dns_resolve_server    = null
    dns_resolve_type      = "A"
    dns_port              = 53
    conditions            = null
  }

  monitor_defs = {
    "technitium-http" = {
      name                  = "Technitium HTTP"
      group                 = "infrastructure"
      kind                  = "http"
      description           = "Пользовательский HTTPS-маршрут Technitium DNS: локальный DNS, TLS, Traefik и веб-панель."
      url                   = "https://dns.${var.domain}/"
      accepted_status_codes = ["200"]
    }

    "technitium-dns" = {
      name               = "Technitium DNS"
      group              = "infrastructure"
      kind               = "dns"
      description        = "Разрешение имени traefik в локальном DNS-сервере Technitium."
      hostname           = "traefik.${var.domain}"
      dns_resolve_server = var.host_ip
      conditions = [
        { variable = "record", operator = "equals", value = var.host_ip },
      ]
    }

    "forgejo-ssh" = {
      name        = "Gitea SSH"
      group       = "infrastructure"
      kind        = "tcp"
      description = "Доступность опубликованного SSH-порта Forgejo через DNS-имя; порт слушает узел, но имя берётся то же, что у остальных маршрутов."
      hostname    = "forgejo.${var.domain}"
      port        = 2222
    }

    "xray-inbound" = {
      name        = "Xray inbound"
      group       = "infrastructure"
      kind        = "tcp"
      description = "Доступность опубликованного TCP-входа Xray; UDP тем же монитором не проверяется."
      hostname    = var.host_ip
      port        = 8443
    }

    "xray-proxy-egress" = {
      name                  = "Xray proxy egress"
      group                 = "infrastructure"
      kind                  = "http"
      description           = "Внешний HTTPS-эндпоинт через прокси-вход Xray: проверяет сам прокси, а не только прямой доступ в интернет."
      url                   = "https://api.telegram.org"
      interval              = 120
      timeout               = 30
      accepted_status_codes = ["200"]
      proxy_key             = "xray"
    }

    "gatus" = {
      name                  = "Gatus"
      group                 = "monitoring"
      kind                  = "http"
      description           = "Пользовательский HTTPS-маршрут Gatus; фиксирует проблемы маршрута, пока сам процесс Gatus способен выполнять проверки."
      url                   = "https://uptime.${var.domain}/"
      accepted_status_codes = ["200"]
    }

    "uptime-kuma" = {
      name                  = "Uptime Kuma"
      group                 = "monitoring"
      kind                  = "http"
      description           = "Собственный HTTPS-маршрут Uptime Kuma; фиксирует проблемы маршрута, пока сам процесс Kuma способен выполнять проверки."
      url                   = "https://kuma.${var.domain}/"
      accepted_status_codes = ["200"]
    }

    "homepage" = {
      name                  = "Homepage"
      group                 = "monitoring"
      kind                  = "http"
      description           = "Health endpoint Homepage через локальный DNS, TLS и Traefik."
      url                   = "https://home.${var.domain}/api/healthcheck"
      accepted_status_codes = ["200"]
    }

    "beszel" = {
      name                  = "Beszel"
      group                 = "monitoring"
      kind                  = "http"
      description           = "Публичный health endpoint Beszel Hub через локальный DNS, TLS и Traefik."
      url                   = "https://beszel.${var.domain}/api/health"
      accepted_status_codes = ["200"]
    }

    "netdata" = {
      name                  = "Netdata"
      group                 = "monitoring"
      kind                  = "http"
      description           = "Агент Netdata в кластере; публичный маршрут закрыт forward auth."
      url                   = "http://netdata.monitoring.svc.cluster.local/api/v1/info"
      accepted_status_codes = ["200"]
    }

    "victoria-metrics" = {
      name                  = "VictoriaMetrics"
      group                 = "monitoring"
      kind                  = "http"
      description           = "TSDB VictoriaMetrics в кластере; наружу не публикуется, /health отдаёт 200 и тело OK."
      url                   = "http://victoriametrics.monitoring.svc.cluster.local/health"
      keyword               = "OK"
      accepted_status_codes = ["200"]
    }

    "vmagent" = {
      name                  = "vmagent"
      group                 = "monitoring"
      kind                  = "http"
      description           = "Сборщик метрик vmagent в кластере; наружу не публикуется, /health отдаёт 200 и тело OK."
      url                   = "http://vmagent.monitoring.svc.cluster.local/health"
      keyword               = "OK"
      accepted_status_codes = ["200"]
    }

    "grafana" = {
      name                  = "Grafana"
      group                 = "monitoring"
      kind                  = "http"
      description           = "Health API Grafana в кластере; публичный маршрут закрыт forward auth. Поле database отражает состояние подключения к TSDB."
      url                   = "http://grafana.monitoring.svc.cluster.local/api/health"
      json_path             = "$.database"
      json_path_operator    = "=="
      expected_value        = "ok"
      accepted_status_codes = ["200"]
    }

    "radar" = {
      name                  = "Radar"
      group                 = "monitoring"
      kind                  = "http"
      description           = "Health API Radar в кластере; публичный маршрут закрыт forward auth."
      url                   = "http://radar.radar.svc.cluster.local/api/health"
      accepted_status_codes = ["200"]
    }

    "wud" = {
      name                  = "WUD"
      group                 = "monitoring"
      kind                  = "http"
      description           = "Health endpoint WUD в кластере; публичный маршрут закрыт forward auth. Тело содержит uptime, то есть агент жив."
      url                   = "http://wud.monitoring.svc.cluster.local/health"
      keyword               = "uptime"
      accepted_status_codes = ["200"]
    }

    "jitsi-meet" = {
      name                  = "Jitsi Meet"
      group                 = "applications"
      kind                  = "http"
      description           = "Пользовательский HTTPS-маршрут Jitsi Meet."
      url                   = "https://meet.${var.domain}/"
      accepted_status_codes = ["200"]
    }

    "mermaid" = {
      name                  = "Mermaid Live Editor"
      group                 = "applications"
      kind                  = "http"
      description           = "Пользовательский HTTPS-маршрут Mermaid Live Editor."
      url                   = "https://mermaid.${var.domain}/"
      accepted_status_codes = ["200"]
    }

    "nextcloud" = {
      name                  = "Nextcloud"
      group                 = "applications"
      kind                  = "http"
      description           = "Публичный status endpoint Nextcloud через локальный DNS, TLS и Traefik. Проверяется только признак установки: у json-query монитора Kuma одно условие, а проверок в Gatus три."
      url                   = "https://nextcloud.${var.domain}/status.php"
      json_path             = "$.installed"
      json_path_operator    = "=="
      expected_value        = "true"
      accepted_status_codes = ["200"]
    }

    "forgejo" = {
      name                  = "Forgejo"
      group                 = "applications"
      kind                  = "http"
      description           = "Публичный health endpoint Forgejo через локальный DNS, TLS и Traefik; также проверяет подключение к PostgreSQL."
      url                   = "https://forgejo.${var.domain}/api/healthz"
      json_path             = "$.status"
      json_path_operator    = "=="
      expected_value        = "pass"
      accepted_status_codes = ["200"]
    }

    "code-server" = {
      name                  = "code-server"
      group                 = "applications"
      kind                  = "http"
      description           = "Health endpoint code-server через локальный DNS, TLS и Traefik; парольная страница IDE не используется для определения состояния."
      url                   = "https://code.${var.domain}/healthz"
      accepted_status_codes = ["200"]
    }

    "authentik" = {
      name                  = "Authentik"
      group                 = "applications"
      kind                  = "http"
      description           = "Readiness endpoint Authentik через локальный DNS, TLS и Traefik; также проверяет подключение к PostgreSQL."
      url                   = "https://auth.${var.domain}/-/health/ready/"
      accepted_status_codes = ["200"]
    }

    "localai" = {
      name                  = "LocalAI"
      group                 = "applications"
      kind                  = "http"
      description           = "Readiness endpoint LocalAI через локальный DNS, TLS и Traefik."
      url                   = "https://localai.${var.domain}/readyz"
      accepted_status_codes = ["200"]
    }

    "open-webui" = {
      name                  = "Open WebUI"
      group                 = "applications"
      kind                  = "http"
      description           = "Пользовательский HTTPS-маршрут Open WebUI через локальный DNS, TLS и Traefik."
      url                   = "https://ai.${var.domain}/health"
      accepted_status_codes = ["200"]
    }

    "immich" = {
      name                  = "Immich"
      group                 = "applications"
      kind                  = "http"
      description           = "Публичный ping endpoint Immich через локальный DNS, TLS и Traefik."
      url                   = "https://immich.${var.domain}/api/server/ping"
      json_path             = "$.res"
      json_path_operator    = "=="
      expected_value        = "pong"
      accepted_status_codes = ["200"]
    }

    "dawarich" = {
      name                  = "Dawarich"
      group                 = "applications"
      kind                  = "http"
      description           = "Публичный health endpoint Dawarich через локальный DNS, TLS и Traefik."
      url                   = "https://dawarich.${var.domain}/api/v1/health"
      json_path             = "$.status"
      json_path_operator    = "=="
      expected_value        = "ok"
      accepted_status_codes = ["200"]
    }

    "jellyfin" = {
      name                  = "Jellyfin"
      group                 = "applications"
      kind                  = "http"
      description           = "Публичный health endpoint Jellyfin через локальный DNS, TLS и Traefik."
      url                   = "https://jellyfin.${var.domain}/health"
      keyword               = "Healthy"
      accepted_status_codes = ["200"]
    }

    "navidrome" = {
      name                  = "Navidrome"
      group                 = "applications"
      kind                  = "http"
      description           = "Публичный ping endpoint Navidrome через локальный DNS, TLS и Traefik; тело ответа — точка."
      url                   = "https://music.${var.domain}/ping"
      keyword               = "."
      accepted_status_codes = ["200"]
    }

    "stirling-pdf" = {
      name                  = "Stirling PDF"
      group                 = "applications"
      kind                  = "http"
      description           = "Публичный status endpoint Stirling PDF через локальный DNS, TLS и Traefik."
      url                   = "https://pdf.${var.domain}/api/v1/info/status"
      json_path             = "$.status"
      json_path_operator    = "=="
      expected_value        = "UP"
      accepted_status_codes = ["200"]
    }

    "home-assistant" = {
      name                  = "Home Assistant"
      group                 = "applications"
      kind                  = "http"
      description           = "Публичный HTTPS-маршрут Home Assistant. HA работает в network_mode: host, его порт 8123 из пода не виден — firewalld режет INPUT для pod-сети, поэтому проверяется публичный маршрут."
      url                   = "https://ha.${var.domain}/"
      accepted_status_codes = ["200"]
    }

    "structurizr" = {
      name                  = "Structurizr"
      group                 = "applications"
      kind                  = "http"
      description           = "Backend Structurizr в кластере; публичный маршрут закрыт forward auth."
      url                   = "http://structurizr.structurizr.svc.cluster.local/"
      accepted_status_codes = ["200"]
    }

    "lute" = {
      name                  = "Lute"
      group                 = "applications"
      kind                  = "http"
      description           = "Пользовательский HTTPS-маршрут Lute через локальный DNS, TLS и Traefik."
      url                   = "https://lute.${var.domain}/"
      accepted_status_codes = ["200"]
    }

    "x3-ui" = {
      name        = "3x-ui"
      group       = "applications"
      kind        = "tcp"
      description = "Доступность web backend 3x-ui внутри кластера; публичный путь панели намеренно не хранится в репозитории."
      hostname    = "xui.3x-ui.svc.cluster.local"
      port        = 2053
    }

    "sure" = {
      name                  = "Sure"
      group                 = "applications"
      kind                  = "http"
      description           = "Форма входа Sure через локальный DNS, TLS и Traefik: корень отдаёт 302, проверяется сама форма."
      url                   = "https://sure.${var.domain}/sessions/new"
      accepted_status_codes = ["200"]
    }

    "mailserver" = {
      name                  = "Mailserver"
      group                 = "applications"
      kind                  = "http"
      description           = "Панель администрирования Stalwart через локальный DNS, TLS и Traefik; корень отдаёт 302 на страницу входа."
      url                   = "https://mailserver.${var.domain}/"
      accepted_status_codes = ["200"]
    }

    "webmail" = {
      name                  = "Webmail"
      group                 = "applications"
      kind                  = "http"
      description           = "Пользовательский HTTPS-маршрут веб-почты через локальный DNS, TLS и Traefik."
      url                   = "https://mail.${var.domain}/"
      accepted_status_codes = ["200"]
    }

    "seafile" = {
      name                  = "Seafile"
      group                 = "applications"
      kind                  = "http"
      description           = "Анонимный ping endpoint Seafile через локальный DNS, TLS и Traefik."
      url                   = "https://seafile.${var.domain}/api2/ping/"
      keyword               = "pong"
      accepted_status_codes = ["200"]
    }

    "onlyoffice" = {
      name                  = "OnlyOffice"
      group                 = "applications"
      kind                  = "http"
      description           = "Healthcheck OnlyOffice Document Server через локальный DNS, TLS и Traefik; тело ответа — JSON true."
      url                   = "https://onlyoffice.${var.domain}/healthcheck"
      json_path             = "$"
      json_path_operator    = "=="
      expected_value        = "true"
      accepted_status_codes = ["200"]
    }

    "paperless" = {
      name                  = "Paperless"
      group                 = "applications"
      kind                  = "http"
      description           = "Веб-интерфейс Paperless-ngx через локальный DNS, TLS и Traefik; корень отдаёт 302 на страницу входа."
      url                   = "https://paperless.${var.domain}/"
      accepted_status_codes = ["200"]
    }

    "infisical" = {
      name                  = "Infisical"
      group                 = "applications"
      kind                  = "http"
      description           = "Status endpoint Infisical через локальный DNS, TLS и Traefik; также отражает доступность Redis и Postgres."
      url                   = "https://infisical.${var.domain}/api/status"
      json_path             = "$.message"
      json_path_operator    = "=="
      expected_value        = "Ok"
      accepted_status_codes = ["200"]
    }

    "zitadel" = {
      name                  = "Zitadel"
      group                 = "applications"
      kind                  = "http"
      description           = "Health endpoint Zitadel через локальный DNS, TLS и Traefik; тело ответа — ok."
      url                   = "https://id.${var.domain}/debug/healthz"
      keyword               = "ok"
      accepted_status_codes = ["200"]
    }

    "element-web" = {
      name                  = "Element Web"
      group                 = "applications"
      kind                  = "http"
      description           = "Пользовательский HTTPS-маршрут Element Web через локальный DNS, TLS и Traefik."
      url                   = "https://element.${var.domain}/"
      accepted_status_codes = ["200"]
    }

    "synapse" = {
      name                  = "Synapse"
      group                 = "applications"
      kind                  = "http"
      description           = "Client-Server API Synapse (/_matrix) через локальный DNS, TLS и Traefik."
      url                   = "https://element.${var.domain}/_matrix/client/versions"
      keyword               = "versions"
      accepted_status_codes = ["200"]
    }

    "talk-signaling" = {
      name                  = "Talk signaling"
      group                 = "applications"
      kind                  = "http"
      description           = "Nextcloud Talk high-performance backend (eturnal) через локальный DNS, TLS и Traefik."
      url                   = "https://talk-signaling.${var.domain}/standalone-signaling/api/v1/welcome"
      keyword               = "Welcome"
      accepted_status_codes = ["200"]
    }

    "traefik" = {
      name                  = "Traefik"
      group                 = "monitoring"
      kind                  = "http"
      description           = "Нативный health endpoint Traefik (/ping) через локальный DNS, TLS и Traefik. Панель /dashboard закрыта oauth2-proxy и на неавторизованный запрос отдаёт 302 на логин, создавая auth request в Zitadel; /ping проверяет живость без авторизации. У Gatus такого монитора нет."
      url                   = "https://traefik.${var.domain}/ping"
      accepted_status_codes = ["200"]
    }

    "actions-dns-coredns" = {
      name               = "Actions DNS via CoreDNS"
      group              = "external"
      kind               = "dns"
      description        = "Разрешение data.forgejo.org через kube-dns: тот же путь, что и у job'ов, тянущих экшены."
      hostname           = "data.forgejo.org"
      dns_resolve_server = var.kube_dns_ip
      interval           = 20
    }

    "actions-dns-technitium" = {
      name               = "Actions DNS via Technitium"
      group              = "external"
      kind               = "dns"
      description        = "Разрешение data.forgejo.org прямым запросом в Technitium: отделяет отказ промежуточного резолвера от недоступности сервиса."
      hostname           = "data.forgejo.org"
      dns_resolve_server = var.host_ip
      interval           = 20
    }

    "actions-upstream" = {
      name                  = "Actions upstream"
      group                 = "external"
      kind                  = "http"
      description           = "Тот же git-эндпоинт, что дёргает раннер при загрузке экшена: проверяет DNS, TLS и HTTP целиком. Корень сайта отдаёт редирект, поэтому не он."
      url                   = "https://data.forgejo.org/actions/checkout/info/refs?service=git-upload-pack"
      interval              = 20
      timeout               = 10
      accepted_status_codes = ["200"]
    }

    "github-dns-coredns" = {
      name               = "GitHub DNS via CoreDNS"
      group              = "external"
      kind               = "dns"
      description        = "Разрешение github.com через kube-dns: публичное зеркало репозитория и источник экшенов."
      hostname           = "github.com"
      dns_resolve_server = var.kube_dns_ip
      interval           = 20
    }

    "github-dns-technitium" = {
      name               = "GitHub DNS via Technitium"
      group              = "external"
      kind               = "dns"
      description        = "Разрешение github.com прямым запросом в Technitium: отделяет отказ промежуточного резолвера от недоступности сервиса."
      hostname           = "github.com"
      dns_resolve_server = var.host_ip
      interval           = 20
    }

    "github-upstream" = {
      name                  = "GitHub upstream"
      group                 = "external"
      kind                  = "http"
      description           = "Корень github.com отдаёт редирект, поэтому проверяется стабильный эндпоинт."
      url                   = "https://github.com/robots.txt"
      interval              = 20
      timeout               = 10
      accepted_status_codes = ["200"]
    }

    "ghcr-dns-coredns" = {
      name               = "GHCR DNS via CoreDNS"
      group              = "external"
      kind               = "dns"
      description        = "Разрешение ghcr.io через kube-dns: источник job-образов."
      hostname           = "ghcr.io"
      dns_resolve_server = var.kube_dns_ip
      interval           = 20
    }

    "ghcr-dns-technitium" = {
      name               = "GHCR DNS via Technitium"
      group              = "external"
      kind               = "dns"
      description        = "Разрешение ghcr.io прямым запросом в Technitium: отделяет отказ промежуточного резолвера от недоступности сервиса."
      hostname           = "ghcr.io"
      dns_resolve_server = var.host_ip
      interval           = 20
    }

    "ghcr-upstream" = {
      name                  = "GHCR upstream"
      group                 = "external"
      kind                  = "http"
      description           = "Без токена реестр отвечает 401, и это же означает, что реестр жив: docker pull сам получает токен."
      url                   = "https://ghcr.io/v2/"
      interval              = 20
      timeout               = 10
      accepted_status_codes = ["401"]
    }

    "dockerhub-dns-coredns" = {
      name               = "Docker Hub DNS via CoreDNS"
      group              = "external"
      kind               = "dns"
      description        = "Разрешение registry-1.docker.io через kube-dns: источник job-образов."
      hostname           = "registry-1.docker.io"
      dns_resolve_server = var.kube_dns_ip
      interval           = 20
    }

    "dockerhub-dns-technitium" = {
      name               = "Docker Hub DNS via Technitium"
      group              = "external"
      kind               = "dns"
      description        = "Разрешение registry-1.docker.io прямым запросом в Technitium: отделяет отказ промежуточного резолвера от недоступности сервиса."
      hostname           = "registry-1.docker.io"
      dns_resolve_server = var.host_ip
      interval           = 20
    }

    "dockerhub-upstream" = {
      name                  = "Docker Hub upstream"
      group                 = "external"
      kind                  = "http"
      description           = "Без токена реестр отвечает 401, и это же означает, что реестр жив."
      url                   = "https://registry-1.docker.io/v2/"
      interval              = 20
      timeout               = 10
      accepted_status_codes = ["401"]
    }

    "google-dns-coredns" = {
      name               = "Google DNS via CoreDNS"
      group              = "external"
      kind               = "dns"
      description        = "Разрешение www.google.com через kube-dns: общий доступ в интернет."
      hostname           = "www.google.com"
      dns_resolve_server = var.kube_dns_ip
      interval           = 20
    }

    "google-dns-technitium" = {
      name               = "Google DNS via Technitium"
      group              = "external"
      kind               = "dns"
      description        = "Разрешение www.google.com прямым запросом в Technitium: отделяет отказ промежуточного резолвера от недоступности сервиса."
      hostname           = "www.google.com"
      dns_resolve_server = var.host_ip
      interval           = 20
    }

    "google-upstream" = {
      name                  = "Google upstream"
      group                 = "external"
      kind                  = "http"
      description           = "Лёгкий эндпоинт generate_204: отдаёт 204, не тянет главную страницу."
      url                   = "https://www.google.com/generate_204"
      interval              = 20
      timeout               = 10
      accepted_status_codes = ["204"]
    }

    "yandex-dns-coredns" = {
      name               = "Yandex DNS via CoreDNS"
      group              = "external"
      kind               = "dns"
      description        = "Разрешение ya.ru через kube-dns: общий доступ в интернет."
      hostname           = "ya.ru"
      dns_resolve_server = var.kube_dns_ip
      interval           = 20
    }

    "yandex-dns-technitium" = {
      name               = "Yandex DNS via Technitium"
      group              = "external"
      kind               = "dns"
      description        = "Разрешение ya.ru прямым запросом в Technitium: отделяет отказ промежуточного резолвера от недоступности сервиса."
      hostname           = "ya.ru"
      dns_resolve_server = var.host_ip
      interval           = 20
    }

    "yandex-upstream" = {
      name                  = "Yandex upstream"
      group                 = "external"
      kind                  = "http"
      description           = "Корень ya.ru отдаёт капчу или редирект, поэтому берётся robots.txt."
      url                   = "https://ya.ru/robots.txt"
      interval              = 20
      timeout               = 10
      accepted_status_codes = ["200"]
    }
  }

  monitors = {
    for key, def in local.monitor_defs : key => merge(local.monitor_defaults, def)
  }
}
