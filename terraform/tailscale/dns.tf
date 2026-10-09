resource "tailscale_dns_configuration" "tailnet" {
  magic_dns          = true
  override_local_dns = false
  search_paths       = []

  split_dns {
    domain = var.domain
    nameservers {
      address            = var.host_ip
      use_with_exit_node = true
    }
  }

  split_dns {
    domain = "biplane.v6.rocks"
    nameservers {
      address            = var.host_ip
      use_with_exit_node = true
    }
  }
}
