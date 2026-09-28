variable "domain" {
  description = "Корневой домен стенда; его зону tailnet отдаёт домашнему DNS"
  type        = string
}

variable "host_ip" {
  description = "Адрес домашнего DNS-сервера (Technitium), которому tailnet отдаёт запросы зоны domain"
  type        = string
}
