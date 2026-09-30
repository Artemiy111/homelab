import {
  to = technitium_record.wildcard
  id = "${var.domain}::*.${var.domain}::A::${var.host_ip}"
}

import {
  to = technitium_record.dns
  id = "${var.domain}::dns.${var.domain}::A::${var.host_ip}"
}

import {
  to = technitium_record.cloudflare_bootstrap_primary
  id = "cloudflare-dns.com::cloudflare-dns.com::A::104.16.123.96"
}

import {
  to = technitium_record.cloudflare_bootstrap_secondary
  id = "cloudflare-dns.com::cloudflare-dns.com::A::104.16.132.229"
}
