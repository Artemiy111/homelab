# Сторона CNPG: те же пути, что и на стороне приложения (ADR 0006,
# правило 2 — одно значение, два потребителя), но своя политика на
# приложение: токен оператора для одной роли не читает пароли других.

resource "vault_policy" "db_authentik" {
  name = "db/authentik"

  policy = <<-EOT
    path "kv/data/authentik/db"     { capabilities = ["read"] }
    path "kv/metadata/authentik/db" { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "db_element" {
  name = "db/element"

  policy = <<-EOT
    path "kv/data/element/db"     { capabilities = ["read"] }
    path "kv/metadata/element/db" { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "db_forgejo" {
  name = "db/forgejo"

  policy = <<-EOT
    path "kv/data/forgejo/db"     { capabilities = ["read"] }
    path "kv/metadata/forgejo/db" { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "db_gatus" {
  name = "db/gatus"

  policy = <<-EOT
    path "kv/data/gatus/db"     { capabilities = ["read"] }
    path "kv/metadata/gatus/db" { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "db_glitchtip" {
  name = "db/glitchtip"

  policy = <<-EOT
    path "kv/data/glitchtip/db"     { capabilities = ["read"] }
    path "kv/metadata/glitchtip/db" { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "db_grafana" {
  name = "db/grafana"

  policy = <<-EOT
    path "kv/data/grafana/db"     { capabilities = ["read"] }
    path "kv/metadata/grafana/db" { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "db_infisical" {
  name = "db/infisical"

  policy = <<-EOT
    path "kv/data/infisical/db"     { capabilities = ["read"] }
    path "kv/metadata/infisical/db" { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "db_nextcloud" {
  name = "db/nextcloud"

  policy = <<-EOT
    path "kv/data/nextcloud/db"     { capabilities = ["read"] }
    path "kv/metadata/nextcloud/db" { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "db_open_webui" {
  name = "db/open-webui"

  policy = <<-EOT
    path "kv/data/open-webui/db"     { capabilities = ["read"] }
    path "kv/metadata/open-webui/db" { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "db_paperless" {
  name = "db/paperless"

  policy = <<-EOT
    path "kv/data/paperless/db"     { capabilities = ["read"] }
    path "kv/metadata/paperless/db" { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "db_postgres" {
  name = "db/postgres"

  policy = <<-EOT
    path "kv/data/postgres/playground"     { capabilities = ["read"] }
    path "kv/metadata/postgres/playground" { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "db_sure" {
  name = "db/sure"

  policy = <<-EOT
    path "kv/data/sure/db"     { capabilities = ["read"] }
    path "kv/metadata/sure/db" { capabilities = ["read", "list"] }
  EOT
}
