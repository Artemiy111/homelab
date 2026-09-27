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

resource "vault_policy" "vmagent" {
  name = "app/vmagent"

  # vmagent читает ключи, которые выпустили чужие сервисы, поэтому пути
  # перечислены по одному на кред. Правило на префикс
  # `kv/data/*/x/monitoring/*` отдало бы vmagent все такие креды разом, а
  # `kv/data/*/*` — вообще все секреты кластера.
  #
  # По мере переноса остальных семи ключей из Secret `vmagent` сюда
  # добавляется по строке на каждый. Их владельцы: forgejo, dawarich,
  # home-assistant, local-ai, technitium, mailserver (stalwart), navidrome.
  policy = <<-EOT
    path "kv/data/uptime-kuma/x/monitoring/uptime-kuma-metrics-api-key" {
      capabilities = ["read"]
    }

    path "kv/metadata/uptime-kuma/x/monitoring/uptime-kuma-metrics-api-key" {
      capabilities = ["read", "list"]
    }
  EOT
}

resource "vault_policy" "poc_reader" {
  name = "poc-reader"

  policy = <<-EOT
    path "kv/data/poc/*"     { capabilities = ["read"] }
    path "kv/metadata/poc/*" { capabilities = ["read", "list"] }
  EOT
}
