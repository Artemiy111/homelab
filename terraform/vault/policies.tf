resource "vault_policy" "terraform" {
  name = "terraform"

  policy = <<-EOT
    path "auth/token/create" {
      capabilities = ["update"]
    }

    path "auth/token/lookup-self" {
      capabilities = ["read"]
    }

    path "sys/capabilities-self" {
      capabilities = ["update"]
    }

    path "sys/policies/acl" {
      capabilities = ["list"]
    }

    path "sys/policies/acl/*" {
      capabilities = ["create", "read", "update", "delete"]
    }

    path "auth/kubernetes/config" {
      capabilities = ["create", "read", "update", "delete"]
    }

    path "auth/kubernetes/role/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }
  EOT
}

resource "vault_policy" "uptime_kuma" {
  name = "app/uptime-kuma"

  policy = <<-EOT
    path "kv/data/uptime-kuma/sync"     { capabilities = ["read"] }
    path "kv/metadata/uptime-kuma/sync" { capabilities = ["read", "list"] }
  EOT
}

resource "vault_policy" "poc_reader" {
  name = "poc-reader"

  policy = <<-EOT
    path "kv/data/poc/*"     { capabilities = ["read"] }
    path "kv/metadata/poc/*" { capabilities = ["read", "list"] }
  EOT
}
