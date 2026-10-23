resource "yandex_dns_zone" "cluster" {
  name                = local.cluster_name
  zone                = local.dns_zone
  public              = true
  deletion_protection = local.deletion_protection
}

resource "yandex_dns_recordset" "api" {
  zone_id = yandex_dns_zone.cluster.id
  name    = "${local.api_fqdn}."
  type    = "A"
  ttl     = 300
  data    = [yandex_vpc_address.api.external_ipv4_address[0].address]
}
