resource "tailscale_dns_configuration" "tailnet" {
  magic_dns          = true
  override_local_dns = false
  search_paths       = []

  split_dns {
    domain = local.domain
    nameservers {
      address            = local.host_ip
      use_with_exit_node = true
    }
  }
}
