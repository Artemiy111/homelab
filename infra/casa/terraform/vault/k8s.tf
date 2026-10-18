resource "vault_kubernetes_auth_backend_config" "kubernetes" {
  backend                = "kubernetes"
  kubernetes_host        = "https://kubernetes.default.svc:443"
  disable_local_ca_jwt   = false
  disable_iss_validation = true
}
