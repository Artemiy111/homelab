variable "domain" {
  description = "Корневой домен стенда; он же имя локальной зоны Technitium. Панель и API — dns.<домен>"
  type        = string
  default = "biplane.casa"
}


variable "host_ip" {
  description = "Адрес сервера: на него резолвятся wildcard и dns-запись зоны domain"
  type        = string
}

variable "api_token" {
  description = "API token пользователя terraform. Пустая строка — провайдер возьмёт TECHNITIUM_API_TOKEN из окружения"
  type        = string
  sensitive   = true
  default     = ""
}
