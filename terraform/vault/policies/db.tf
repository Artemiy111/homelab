# Политики приложений, у которых есть базовый пароль БД. Он вынесен в отдельный
# путь `db`, потому что то же значение читает CNPG из своего неймспейса
# (правило 2 ADR 0006), и его ротация не должна затрагивать остальное.

resource "vault_policy" "authentik" {
  name = "app/authentik"

  policy = <<-EOT
    path "kv/data/authentik/db"           { capabilities = ["read"] }
    path "kv/metadata/authentik/db"       { capabilities = ["read", "list"] }
    path "kv/data/authentik/secrets"      { capabilities = ["read"] }
    path "kv/metadata/authentik/secrets"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "glitchtip" {
  name = "app/glitchtip"

  policy = <<-EOT
    path "kv/data/glitchtip/db"           { capabilities = ["read"] }
    path "kv/metadata/glitchtip/db"       { capabilities = ["read", "list"] }
    path "kv/data/glitchtip/secrets"      { capabilities = ["read"] }
    path "kv/metadata/glitchtip/secrets"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "immich" {
  name = "app/immich"

  policy = <<-EOT
    path "kv/data/immich/db"      { capabilities = ["read"] }
    path "kv/metadata/immich/db"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "infisical" {
  name = "app/infisical"

  policy = <<-EOT
    path "kv/data/infisical/db"           { capabilities = ["read"] }
    path "kv/metadata/infisical/db"       { capabilities = ["read", "list"] }
    path "kv/data/infisical/secrets"      { capabilities = ["read"] }
    path "kv/metadata/infisical/secrets"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "open_webui" {
  name = "app/open-webui"

  policy = <<-EOT
    path "kv/data/open-webui/db"           { capabilities = ["read"] }
    path "kv/metadata/open-webui/db"       { capabilities = ["read", "list"] }
    path "kv/data/open-webui/secrets"      { capabilities = ["read"] }
    path "kv/metadata/open-webui/secrets"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "paperless" {
  name = "app/paperless"

  policy = <<-EOT
    path "kv/data/paperless/db"           { capabilities = ["read"] }
    path "kv/metadata/paperless/db"       { capabilities = ["read", "list"] }
    path "kv/data/paperless/secrets"      { capabilities = ["read"] }
    path "kv/metadata/paperless/secrets"  { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "postgres" {
  name = "app/postgres"

  policy = <<-EOT
    path "kv/data/postgres/playground"      { capabilities = ["read"] }
    path "kv/metadata/postgres/playground"  { capabilities = ["read", "list"] }
    path "kv/data/postgres/pgweb"           { capabilities = ["read"] }
    path "kv/metadata/postgres/pgweb"       { capabilities = ["read", "list"] }
  EOT
}
