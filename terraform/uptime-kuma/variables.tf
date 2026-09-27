variable "domain" {
  description = "Домен, который Technitium резолвит на адрес сервера"
  type        = string
}

variable "host_ip" {
  description = "Адрес сервера во внутренней сети"
  type        = string
}

variable "kube_dns_ip" {
  description = "ClusterIP сервиса kube-dns"
  type        = string
}

variable "timezone" {
  description = "Часовой пояс, тот же, что в platform/homelab"
  type        = string
}
