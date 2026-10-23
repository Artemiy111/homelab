resource "technitium_zone" "domain_zone" {
  name = local.domain
  type = "Primary"
}

resource "technitium_record" "apex" {
  zone       = local.domain
  name       = local.domain
  type       = "A"
  value      = local.host_ip
  ttl        = 3600
  depends_on = [technitium_zone.domain_zone]
}

resource "technitium_record" "wildcard" {
  zone       = local.domain
  name       = "*.${local.domain}"
  type       = "A"
  value      = local.host_ip
  ttl        = 3600
  depends_on = [technitium_zone.domain_zone]
}

resource "technitium_record" "ts_wildcard" {
  zone       = local.domain
  name       = "*.ts.${local.domain}"
  type       = "A"
  value      = local.host_ip
  ttl        = 3600
  depends_on = [technitium_zone.domain_zone]
}

resource "technitium_record" "dns" {
  zone       = local.domain
  name       = "dns.${local.domain}"
  type       = "A"
  value      = local.host_ip
  ttl        = 3600
  depends_on = [technitium_zone.domain_zone]
}

resource "technitium_record" "delegation" {
  for_each = local.delegation_records

  zone       = local.domain
  name       = "${each.value.subdomain}.${local.domain}"
  type       = "NS"
  value      = each.value.nameserver
  ttl        = 3600
  overwrite  = false
  depends_on = [technitium_zone.domain_zone]
}

resource "technitium_zone" "cloudflare_dns_zone" {
  name = "cloudflare-dns.com"
  type = "Primary"
}

resource "technitium_record" "cloudflare_dns_primary" {
  zone       = "cloudflare-dns.com"
  name       = "cloudflare-dns.com"
  type       = "A"
  value      = "104.16.123.96"
  ttl        = 3600
  overwrite  = false
  depends_on = [technitium_zone.cloudflare_dns_zone]
}

resource "technitium_record" "cloudflare_dns_secondary" {
  zone       = "cloudflare-dns.com"
  name       = "cloudflare-dns.com"
  type       = "A"
  value      = "104.16.132.229"
  ttl        = 3600
  overwrite  = false
  depends_on = [technitium_zone.cloudflare_dns_zone]
}

resource "technitium_record" "zone_ns" {
  zone       = local.domain
  name       = local.domain
  type       = "NS"
  value      = "dns.${local.domain}"
  ttl        = 3600
  overwrite  = true
  depends_on = [technitium_zone.domain_zone]
}
