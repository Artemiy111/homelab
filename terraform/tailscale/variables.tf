variable "domain" {
  description = "Homelab domain"
  type        = string
  default     = "biplane.casa"
}

variable "host_ip" {
  description = "Адрес домашнего DNS-сервера (Technitium), которому tailnet отдаёт запросы зоны domain"
  type        = string
}
