variable "jwt_profile_file" {
  description = "Путь к JSON-ключу service account Zitadel (private key JWT). Сам ключ в репозитории не лежит"
  type        = string
  default     = "~/.config/homelab/zitadel-terraform.json"
}
