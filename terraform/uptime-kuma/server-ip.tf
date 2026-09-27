data "external" "server_ip" {
  count = var.host_ip == null ? 1 : 0

  program = [
    "sh", "-c",
    "ip=$(dig +short A dns.${var.domain} | head -1); [ -n \"$ip\" ] || { echo 'A-запись dns.${var.domain} не найдена' >&2; exit 1; }; echo \"$ip\"",
  ]
}

locals {
  server_ip = var.host_ip != null ? var.host_ip : data.external.server_ip[0].result.ip
}
