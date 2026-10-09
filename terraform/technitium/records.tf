resource "technitium_zone" "domain_zone" {
  name = var.domain
  type = "Primary"
}

resource "technitium_record" "wildcard" {
  zone  = var.domain
  name  = "*.${var.domain}"
  type  = "A"
  value = var.host_ip
  ttl   = 3600
}

resource "technitium_record" "dns" {
  zone  = var.domain
  name  = "dns.${var.domain}"
  type  = "A"
  value = var.host_ip
  ttl   = 3600
}

resource "technitium_zone" "domain_zone_new" {
  name = var.domain_new
  type = "Primary"
}


resource "technitium_record" "wildcard_new" {
  zone  = var.domain_new
  name  = "*.${var.domain_new}"
  type  = "A"
  value = var.host_ip
  ttl   = 3600
}

resource "technitium_record" "dns_new" {
  zone  = var.domain_new
  name  = "dns.${var.domain_new}"
  type  = "A"
  value = var.host_ip
  ttl   = 3600
}

resource "technitium_zone" "cloudflare_dns_zone" {
  name = "cloudflare-dns.com"
  type = "Primary"
}

resource "technitium_record" "cloudflare_dns_primary" {
  zone      = "cloudflare-dns.com"
  name      = "cloudflare-dns.com"
  type      = "A"
  value     = "104.16.123.96"
  ttl       = 3600
  overwrite = false
}

resource "technitium_record" "cloudflare_dns_secondary" {
  zone      = "cloudflare-dns.com"
  name      = "cloudflare-dns.com"
  type      = "A"
  value     = "104.16.132.229"
  ttl       = 3600
  overwrite = false
}
