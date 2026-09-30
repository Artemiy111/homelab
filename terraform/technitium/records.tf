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

resource "technitium_record" "cloudflare_bootstrap_primary" {
  zone      = "cloudflare-dns.com"
  name      = "cloudflare-dns.com"
  type      = "A"
  value     = "104.16.123.96"
  ttl       = 3600
  overwrite = false
}

resource "technitium_record" "cloudflare_bootstrap_secondary" {
  zone      = "cloudflare-dns.com"
  name      = "cloudflare-dns.com"
  type      = "A"
  value     = "104.16.132.229"
  ttl       = 3600
  overwrite = false
}
