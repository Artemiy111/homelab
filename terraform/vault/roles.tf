# Роль на приложение: ServiceAccount `vso-<app>` в своём неймспейсе, политика
# `app/<app>`. Одна роль на приложение — общий токен на два приложения раскрыл бы
# секреты обоих.
locals {
  app_roles = {
    "3x-ui"          = { namespace = "3x-ui", policy = "app/3x-ui" },
    "ats"            = { namespace = "ats", policy = "app/ats" },
    "authentik"      = { namespace = "authentik", policy = "app/authentik" },
    "beszel"         = { namespace = "beszel", policy = "app/beszel" },
    "dawarich"       = { namespace = "dawarich", policy = "app/dawarich" },
    "element"        = { namespace = "element", policy = "app/element" },
    "forgejo"        = { namespace = "forgejo", policy = "app/forgejo" },
    "gatus"          = { namespace = "monitoring", policy = "app/gatus" },
    "glitchtip"      = { namespace = "glitchtip", policy = "app/glitchtip" },
    "grafana"        = { namespace = "monitoring", policy = "app/grafana" },
    "headlamp"       = { namespace = "headlamp", policy = "app/headlamp" },
    "home-assistant" = { namespace = "home-assistant", policy = "app/home-assistant" },
    "immich"         = { namespace = "immich", policy = "app/immich" },
    "infisical"      = { namespace = "infisical", policy = "app/infisical" },
    "jellyfin"       = { namespace = "jellyfin", policy = "app/jellyfin" },
    "jitsi"          = { namespace = "jitsi", policy = "app/jitsi" },
    "local-ai"       = { namespace = "local-ai", policy = "app/local-ai" },
    "mailserver"     = { namespace = "mailserver", policy = "app/mailserver" },
    "navidrome"      = { namespace = "navidrome", policy = "app/navidrome" },
    "nextcloud"      = { namespace = "nextcloud", policy = "app/nextcloud" },
    "oauth2-proxy"   = { namespace = "oauth2-proxy", policy = "app/oauth2-proxy" },
    "open-webui"     = { namespace = "open-webui", policy = "app/open-webui" },
    "paperless"      = { namespace = "paperless", policy = "app/paperless" },
    "pdf"            = { namespace = "pdf", policy = "app/pdf" },
    "postgres"       = { namespace = "postgres", policy = "app/postgres" },
    "rustfs"         = { namespace = "rustfs", policy = "app/rustfs" },
    "seafile"        = { namespace = "seafile", policy = "app/seafile" },
    "sure"           = { namespace = "sure", policy = "app/sure" },
    "talk-hpb"       = { namespace = "talk-hpb", policy = "app/talk-hpb" },
    "technitium"     = { namespace = "technitium", policy = "app/technitium" },
    "uptime-kuma"    = { namespace = "uptime-kuma", policy = "app/uptime-kuma" },
    "vmagent"        = { namespace = "monitoring", policy = "app/vmagent" },
  }
  # Сторона CNPG в неймспейсе databases: по роли на приложение, чтобы
  # токен оператора для одной роли не доставал пароли других.
  db_roles = {
    "authentik-db"  = { namespace = "databases", policy = "db/authentik" },
    "element-db"    = { namespace = "databases", policy = "db/element" },
    "forgejo-db"    = { namespace = "databases", policy = "db/forgejo" },
    "gatus-db"      = { namespace = "databases", policy = "db/gatus" },
    "glitchtip-db"  = { namespace = "databases", policy = "db/glitchtip" },
    "grafana-db"    = { namespace = "databases", policy = "db/grafana" },
    "infisical-db"  = { namespace = "databases", policy = "db/infisical" },
    "nextcloud-db"  = { namespace = "databases", policy = "db/nextcloud" },
    "open-webui-db" = { namespace = "databases", policy = "db/open-webui" },
    "paperless-db"  = { namespace = "databases", policy = "db/paperless" },
    "postgres-db"   = { namespace = "databases", policy = "db/postgres" },
    "sure-db"       = { namespace = "databases", policy = "db/sure" },
  }
}

resource "vault_kubernetes_auth_backend_role" "app" {
  for_each = local.app_roles

  backend                          = "kubernetes"
  role_name                        = each.key
  audience                         = "vault"
  bound_service_account_names      = ["vso-${each.key}"]
  bound_service_account_namespaces = [each.value.namespace]
  token_policies                   = [each.value.policy]
  token_ttl                        = 3600
}

# Роли для чтения базовых паролей ролей CNPG (см. policies-db.tf).
resource "vault_kubernetes_auth_backend_role" "db" {
  for_each = local.db_roles

  backend                          = "kubernetes"
  role_name                        = each.key
  audience                         = "vault"
  bound_service_account_names      = ["vso-${each.key}"]
  bound_service_account_namespaces = [each.value.namespace]
  token_policies                   = [each.value.policy]
  token_ttl                        = 3600
}

