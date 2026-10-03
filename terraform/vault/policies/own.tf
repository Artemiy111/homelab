# Политики приложений, у которых нет ни базового пароля БД, ни выданных
# кредов: все секреты принадлежат самому приложению (правило 1 ADR 0006).

resource "vault_policy" "app_3x_ui" {
  name = "app/3x-ui"

  policy = <<-EOT
    path "kv/data/3x-ui/admin"      { capabilities = ["read"] }
    path "kv/metadata/3x-ui/admin"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_ats" {
  name = "app/ats"

  policy = <<-EOT
    path "kv/data/ats/purge-token"      { capabilities = ["read"] }
    path "kv/metadata/ats/purge-token"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_beszel" {
  name = "app/beszel"

  policy = <<-EOT
    path "kv/data/beszel/agent"      { capabilities = ["read"] }
    path "kv/metadata/beszel/agent"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_dns01_webhook" {
  name = "app/dns01-webhook"

  policy = <<-EOT
    path "kv/data/dns01-webhook/dynv6"      { capabilities = ["read"] }
    path "kv/metadata/dns01-webhook/dynv6"  { capabilities = ["read", "list"] }
    path "kv/data/dns01-webhook/spaceship"  { capabilities = ["read"] }
    path "kv/metadata/dns01-webhook/spaceship"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_headlamp" {
  name = "app/headlamp"

  policy = <<-EOT
    path "kv/data/headlamp/oidc"      { capabilities = ["read"] }
    path "kv/metadata/headlamp/oidc"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_home_assistant" {
  name = "app/home-assistant"

  policy = <<-EOT
    path "kv/data/home-assistant/oidc"      { capabilities = ["read"] }
    path "kv/metadata/home-assistant/oidc"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_jellyfin" {
  name = "app/jellyfin"

  policy = <<-EOT
    path "kv/data/jellyfin/api-key"      { capabilities = ["read"] }
    path "kv/metadata/jellyfin/api-key"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_jitsi" {
  name = "app/jitsi"

  policy = <<-EOT
    path "kv/data/jitsi/auth"      { capabilities = ["read"] }
    path "kv/metadata/jitsi/auth"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_local_ai" {
  name = "app/local-ai"

  policy = <<-EOT
    path "kv/data/local-ai/api-key"      { capabilities = ["read"] }
    path "kv/metadata/local-ai/api-key"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_navidrome" {
  name = "app/navidrome"

  policy = <<-EOT
    path "kv/data/navidrome/@monitoring/navidrome-metrics-path"     { capabilities = ["read"] }
    path "kv/metadata/navidrome/@monitoring/navidrome-metrics-path" { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_oauth2_proxy" {
  name = "app/oauth2-proxy"

  policy = <<-EOT
    path "kv/data/oauth2-proxy/oidc"         { capabilities = ["read"] }
    path "kv/metadata/oauth2-proxy/oidc"     { capabilities = ["read", "list"] }
    path "kv/data/oauth2-proxy/session"      { capabilities = ["read"] }
    path "kv/metadata/oauth2-proxy/session"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_pdf" {
  name = "app/pdf"

  policy = <<-EOT
    path "kv/data/pdf/admin"      { capabilities = ["read"] }
    path "kv/metadata/pdf/admin"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_radar" {
  name = "app/radar"

  policy = <<-EOT
    path "kv/data/radar/oidc"      { capabilities = ["read"] }
    path "kv/metadata/radar/oidc"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_rustfs" {
  name = "app/rustfs"

  policy = <<-EOT
    path "kv/data/rustfs/credentials"      { capabilities = ["read"] }
    path "kv/metadata/rustfs/credentials"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_talk_hpb" {
  name = "app/talk-hpb"

  policy = <<-EOT
    path "kv/data/talk-hpb/secrets"      { capabilities = ["read"] }
    path "kv/metadata/talk-hpb/secrets"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_uptime_kuma" {
  name = "app/uptime-kuma"

  policy = <<-EOT
    path "kv/data/uptime-kuma/db"        { capabilities = ["read"] }
    path "kv/metadata/uptime-kuma/db"    { capabilities = ["read", "list"] }
    path "kv/data/uptime-kuma/root"      { capabilities = ["read"] }
    path "kv/metadata/uptime-kuma/root"  { capabilities = ["read", "list"] }
  EOT
}
