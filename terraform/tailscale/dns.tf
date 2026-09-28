resource "tailscale_dns_configuration" "tailnet" {
  magic_dns          = true
  override_local_dns = false

  split_dns {
    domain = var.domain

    nameservers {
      address = var.host_ip
    }
  }
}
