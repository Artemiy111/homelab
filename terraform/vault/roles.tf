resource "vault_kubernetes_auth_backend_role" "vso_reader" {
  backend                          = "kubernetes"
  role_name                        = "vso-reader"
  audience                         = "vault"
  bound_service_account_names      = ["vso-vault-auth"]
  bound_service_account_namespaces = ["vault"]
  token_policies                   = ["vso-reader"]
  token_ttl                        = 3600
}

resource "vault_kubernetes_auth_backend_role" "vso_uptime_kuma" {
  backend                          = "kubernetes"
  role_name                        = "vso-uptime-kuma"
  audience                         = "vault"
  bound_service_account_names      = ["vso-uptime-kuma"]
  bound_service_account_namespaces = ["uptime-kuma"]
  token_policies                   = ["app/uptime-kuma"]
  token_ttl                        = 3600
}
