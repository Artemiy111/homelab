variable "domain" {
  description = "Домен, который Technitium резолвит на адрес сервера"
  type        = string
}

variable "host_ip" {
  description = "Адрес сервера. Если не задан, берётся из A-записи dns.<домен> на машине, где запущен terraform"
  type        = string
  default     = null
}

variable "timezone" {
  description = "Часовой пояс, тот же, что в clusters/casa/platform/homelab"
  type        = string
}
