# Политики приложений, у которых нет ни базового пароля БД, ни выданных
# кредов: все секреты принадлежат самому приложению (правило 1 ADR 0006).

resource "vault_policy" "3x_ui" {
  name = "app/3x-ui"

  policy = <<-EOT
    path "kv/data/3x-ui/admin"      { capabilities = ["read"] }
    path "kv/metadata/3x-ui/admin"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "ats" {
  name = "app/ats"

  policy = <<-EOT
    path "kv/data/ats/purge-token"      { capabilities = ["read"] }
    path "kv/metadata/ats/purge-token"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "beszel" {
  name = "app/beszel"

  policy = <<-EOT
    path "kv/data/beszel/agent"      { capabilities = ["read"] }
    path "kv/metadata/beszel/agent"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "home_assistant" {
  name = "app/home-assistant"

  policy = <<-EOT
    path "kv/data/home-assistant/oidc"      { capabilities = ["read"] }
    path "kv/metadata/home-assistant/oidc"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "jellyfin" {
  name = "app/jellyfin"

  policy = <<-EOT
    path "kv/data/jellyfin/api-key"      { capabilities = ["read"] }
    path "kv/metadata/jellyfin/api-key"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "jitsi" {
  name = "app/jitsi"

  policy = <<-EOT
    path "kv/data/jitsi/auth"      { capabilities = ["read"] }
    path "kv/metadata/jitsi/auth"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "local_ai" {
  name = "app/local-ai"

  policy = <<-EOT
    path "kv/data/local-ai/api-key"      { capabilities = ["read"] }
    path "kv/metadata/local-ai/api-key"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "navidrome" {
  name = "app/navidrome"

  policy = <<-EOT
    path "kv/data/navidrome/metrics-path"      { capabilities = ["read"] }
    path "kv/metadata/navidrome/metrics-path"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "oauth2_proxy" {
  name = "app/oauth2-proxy"

  policy = <<-EOT
    path "kv/data/oauth2-proxy/oidc"         { capabilities = ["read"] }
    path "kv/metadata/oauth2-proxy/oidc"     { capabilities = ["read", "list"] }
    path "kv/data/oauth2-proxy/session"      { capabilities = ["read"] }
    path "kv/metadata/oauth2-proxy/session"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "pdf" {
  name = "app/pdf"

  policy = <<-EOT
    path "kv/data/pdf/admin"      { capabilities = ["read"] }
    path "kv/metadata/pdf/admin"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "rustfs" {
  name = "app/rustfs"

  policy = <<-EOT
    path "kv/data/rustfs/credentials"      { capabilities = ["read"] }
    path "kv/metadata/rustfs/credentials"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "talk_hpb" {
  name = "app/talk-hpb"

  policy = <<-EOT
    path "kv/data/talk-hpb/secrets"      { capabilities = ["read"] }
    path "kv/metadata/talk-hpb/secrets"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "uptime_kuma" {
  name = "app/uptime-kuma"

  policy = <<-EOT
    path "kv/data/uptime-kuma/sync"      { capabilities = ["read"] }
    path "kv/metadata/uptime-kuma/sync"  { capabilities = ["read", "list"] }
  EOT
}
