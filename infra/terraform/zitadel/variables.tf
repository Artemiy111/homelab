variable "domain" {
  description = "Корневой домен стенда, без схемы: адрес Zitadel собирается как id.<домен>, как в clusters/casa/apps/zitadel. Из него же собираются домен организации и redirect URI приложений"
  type        = string
}

variable "jwt_profile_file" {
  description = "Путь к JSON-ключу service account Zitadel (private key JWT). Сам ключ в репозитории не лежит"
  type        = string
  default     = "~/.config/homelab/zitadel-terraform.json"
}
