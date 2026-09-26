resource "vault_kubernetes_auth_backend_role" "vso_reader" {
  backend                          = "kubernetes"
  role_name                        = "vso-reader"
  audience                         = "vault"
  bound_service_account_names      = ["vso-vault-auth"]
  bound_service_account_namespaces = ["vault"]
  token_policies                   = ["vso-reader"]
  token_ttl                        = 3600
}
