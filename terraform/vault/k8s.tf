# Конфигурация метода аутентификации kubernetes, а не ролей: роли лежат в
# roles.tf, здесь то, как Vault вообще проверяет сервис-аккаунт.
#
# kubernetes_host указывает на API кластера изнутри, поэтому kubernetes_ca_cert
# и token_reviewer_jwt не заданы: при disable_local_ca_jwt = false Vault берёт
# локальный CA и собственный токен пода. Если задать token_reviewer_jwt, он
# попадёт в state открытым текстом — тогда нужен вариант _wo.
#
# disable_iss_validation = true отключает проверку издателя JWT. Это ослабление
# выставлено в Vault руками, здесь оно просто зафиксировано.
resource "vault_kubernetes_auth_backend_config" "kubernetes" {
  backend                = "kubernetes"
  kubernetes_host        = "https://kubernetes.default.svc:443"
  disable_local_ca_jwt   = false
  disable_iss_validation = true
}
