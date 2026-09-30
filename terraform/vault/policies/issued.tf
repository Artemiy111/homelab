# Политики приложений, которые выдают креды наружу. Такой кред лежит под
# сегментом `@` и его можно отозвать, не переписывая остальные секреты
# приложения (правило 3 ADR 0006). Строки на чужое выданное значение —
# например, `kv/ntfy/topic` — пишутся здесь явно, wildcard не используется.

resource "vault_policy" "app_dawarich" {
  name = "app/dawarich"

  policy = <<-EOT
    path "kv/data/dawarich/db"                                         { capabilities = ["read"] }
    path "kv/metadata/dawarich/db"                                     { capabilities = ["read", "list"] }
    path "kv/data/dawarich/secrets"                                    { capabilities = ["read"] }
    path "kv/metadata/dawarich/secrets"                                { capabilities = ["read", "list"] }
    path "kv/data/dawarich/@monitoring/dawarich-metrics-password"     { capabilities = ["read"] }
    path "kv/metadata/dawarich/@monitoring/dawarich-metrics-password" { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_element" {
  name = "app/element"

  policy = <<-EOT
    path "kv/data/element/db"          { capabilities = ["read"] }
    path "kv/metadata/element/db"      { capabilities = ["read", "list"] }
    path "kv/data/element/secrets"     { capabilities = ["read"] }
    path "kv/metadata/element/secrets" { capabilities = ["read", "list"] }
    path "kv/data/element/oidc"        { capabilities = ["read"] }
    path "kv/metadata/element/oidc"    { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_forgejo" {
  name = "app/forgejo"

  policy = <<-EOT
    path "kv/data/forgejo/admin"                                  { capabilities = ["read"] }
    path "kv/metadata/forgejo/admin"                              { capabilities = ["read", "list"] }
    path "kv/data/forgejo/runner"                                 { capabilities = ["read"] }
    path "kv/metadata/forgejo/runner"                             { capabilities = ["read", "list"] }
    path "kv/data/forgejo/db"                                     { capabilities = ["read"] }
    path "kv/metadata/forgejo/db"                                 { capabilities = ["read", "list"] }
    path "kv/data/forgejo/oidc"                                   { capabilities = ["read"] }
    path "kv/metadata/forgejo/oidc"                               { capabilities = ["read", "list"] }
    path "kv/data/forgejo/@monitoring/forgejo-metrics-token"     { capabilities = ["read"] }
    path "kv/metadata/forgejo/@monitoring/forgejo-metrics-token" { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_gatus" {
  name = "app/gatus"

  policy = <<-EOT
    path "kv/data/gatus/db"                                   { capabilities = ["read"] }
    path "kv/metadata/gatus/db"                               { capabilities = ["read", "list"] }
    path "kv/data/gatus/@telegram/telegram-notification"      { capabilities = ["read"] }
    path "kv/metadata/gatus/@telegram/telegram-notification"  { capabilities = ["read", "list"] }
    path "kv/data/ntfy/topic"                                 { capabilities = ["read"] }
    path "kv/metadata/ntfy/topic"                             { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_grafana" {
  name = "app/grafana"

  policy = <<-EOT
    path "kv/data/grafana/admin"      { capabilities = ["read"] }
    path "kv/metadata/grafana/admin"  { capabilities = ["read", "list"] }
    path "kv/data/grafana/db"         { capabilities = ["read"] }
    path "kv/metadata/grafana/db"     { capabilities = ["read", "list"] }
    path "kv/data/ntfy/topic"         { capabilities = ["read"] }
    path "kv/metadata/ntfy/topic"     { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_mailserver" {
  name = "app/mailserver"

  policy = <<-EOT
    path "kv/data/mailserver/admin"                                      { capabilities = ["read"] }
    path "kv/metadata/mailserver/admin"                                  { capabilities = ["read", "list"] }
    path "kv/data/mailserver/@monitoring/stalwart-metrics-password"     { capabilities = ["read"] }
    path "kv/metadata/mailserver/@monitoring/stalwart-metrics-password" { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_nextcloud" {
  name = "app/nextcloud"

  policy = <<-EOT
    path "kv/data/nextcloud/db"                                          { capabilities = ["read"] }
    path "kv/metadata/nextcloud/db"                                      { capabilities = ["read", "list"] }
    path "kv/data/nextcloud/admin"                                       { capabilities = ["read"] }
    path "kv/metadata/nextcloud/admin"                                   { capabilities = ["read", "list"] }
    path "kv/data/nextcloud/@monitoring/nextcloud-metrics-password"     { capabilities = ["read"] }
    path "kv/metadata/nextcloud/@monitoring/nextcloud-metrics-password" { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_seafile" {
  name = "app/seafile"

  policy = <<-EOT
    path "kv/data/seafile/db"          { capabilities = ["read"] }
    path "kv/metadata/seafile/db"      { capabilities = ["read", "list"] }
    path "kv/data/seafile/root"        { capabilities = ["read"] }
    path "kv/metadata/seafile/root"    { capabilities = ["read", "list"] }
    path "kv/data/seafile/secrets"     { capabilities = ["read"] }
    path "kv/metadata/seafile/secrets" { capabilities = ["read", "list"] }
    path "kv/data/seafile/oidc"        { capabilities = ["read"] }
    path "kv/metadata/seafile/oidc"    { capabilities = ["read", "list"] }
    path "kv/data/seafile/@monitoring/seafile-metrics-password"     { capabilities = ["read"] }
    path "kv/metadata/seafile/@monitoring/seafile-metrics-password" { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_sure" {
  name = "app/sure"

  policy = <<-EOT
    path "kv/data/sure/db"                                  { capabilities = ["read"] }
    path "kv/metadata/sure/db"                              { capabilities = ["read", "list"] }
    path "kv/data/sure/secrets"                             { capabilities = ["read"] }
    path "kv/metadata/sure/secrets"                         { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_technitium" {
  name = "app/technitium"

  policy = <<-EOT
    path "kv/data/technitium/admin"                                     { capabilities = ["read"] }
    path "kv/metadata/technitium/admin"                                 { capabilities = ["read", "list"] }
    path "kv/data/technitium/@monitoring/technitium-metrics-token"     { capabilities = ["read"] }
    path "kv/metadata/technitium/@monitoring/technitium-metrics-token" { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "app_vmagent" {
  name = "app/vmagent"

  policy = <<-EOT
    path "kv/data/dawarich/@monitoring/dawarich-metrics-password"          { capabilities = ["read"] }
    path "kv/metadata/dawarich/@monitoring/dawarich-metrics-password"      { capabilities = ["read", "list"] }
    path "kv/data/forgejo/@monitoring/forgejo-metrics-token"               { capabilities = ["read"] }
    path "kv/metadata/forgejo/@monitoring/forgejo-metrics-token"           { capabilities = ["read", "list"] }
    path "kv/data/mailserver/@monitoring/stalwart-metrics-password"        { capabilities = ["read"] }
    path "kv/metadata/mailserver/@monitoring/stalwart-metrics-password"    { capabilities = ["read", "list"] }
    path "kv/data/nextcloud/@monitoring/nextcloud-metrics-password"        { capabilities = ["read"] }
    path "kv/metadata/nextcloud/@monitoring/nextcloud-metrics-password"    { capabilities = ["read", "list"] }
    path "kv/data/technitium/@monitoring/technitium-metrics-token"         { capabilities = ["read"] }
    path "kv/metadata/technitium/@monitoring/technitium-metrics-token"     { capabilities = ["read", "list"] }
    path "kv/data/uptime-kuma/@monitoring/uptime-kuma-metrics-api-key"     { capabilities = ["read"] }
    path "kv/metadata/uptime-kuma/@monitoring/uptime-kuma-metrics-api-key" { capabilities = ["read", "list"] }
    path "kv/data/local-ai/@monitoring/localai-api-key"                    { capabilities = ["read"] }
    path "kv/metadata/local-ai/@monitoring/localai-api-key"                { capabilities = ["read", "list"] }
    path "kv/data/home-assistant/@monitoring/home-assistant-token"         { capabilities = ["read"] }
    path "kv/metadata/home-assistant/@monitoring/home-assistant-token"     { capabilities = ["read", "list"] }
    path "kv/data/navidrome/@monitoring/navidrome-metrics-path"            { capabilities = ["read"] }
    path "kv/metadata/navidrome/@monitoring/navidrome-metrics-path"        { capabilities = ["read", "list"] }
    path "kv/data/seafile/@monitoring/seafile-metrics-password"            { capabilities = ["read"] }
    path "kv/metadata/seafile/@monitoring/seafile-metrics-password"        { capabilities = ["read", "list"] }
  EOT
}

