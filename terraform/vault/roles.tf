resource "vault_kubernetes_auth_backend_role" "poc_reader" {
  backend                          = "kubernetes"
  role_name                        = "poc-reader"
  audience                         = "vault"
  bound_service_account_names      = ["vso-poc-reader"]
  bound_service_account_namespaces = ["vault"]
  token_policies                   = ["poc-reader"]
  token_ttl                        = 3600
}

resource "vault_kubernetes_auth_backend_role" "uptime_kuma" {
  backend                          = "kubernetes"
  role_name                        = "uptime-kuma"
  audience                         = "vault"
  bound_service_account_names      = ["vso-uptime-kuma"]
  bound_service_account_namespaces = ["uptime-kuma"]
  token_policies                   = ["app/uptime-kuma"]
  token_ttl                        = 3600
}

resource "vault_kubernetes_auth_backend_role" "vmagent" {
  backend                          = "kubernetes"
  role_name                        = "vmagent"
  audience                         = "vault"
  bound_service_account_names      = ["vso-vmagent"]
  bound_service_account_namespaces = ["monitoring"]
  token_policies                   = ["app/vmagent"]
  token_ttl                        = 3600
}
