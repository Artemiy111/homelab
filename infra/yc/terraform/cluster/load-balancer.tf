resource "yandex_vpc_address" "api" {
  name                = local.lb_name
  deletion_protection = local.deletion_protection

  external_ipv4_address {
    zone_id = "ru-central1-e"
  }
}

resource "yandex_lb_target_group" "nodes" {
  name      = local.lb_name
  region_id = local.region_id

  dynamic "target" {
    for_each = yandex_compute_instance.node

    content {
      subnet_id = target.value.network_interface[0].subnet_id
      address   = target.value.network_interface[0].ip_address
    }
  }
}

resource "yandex_lb_network_load_balancer" "api" {
  name                = local.lb_name
  type                = "external"
  region_id           = local.region_id
  deletion_protection = local.deletion_protection

  listener {
    name        = "kube-api"
    port        = local.api_port
    target_port = local.api_port
    protocol    = "tcp"

    external_address_spec {
      address    = yandex_vpc_address.api.external_ipv4_address[0].address
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.nodes.id

    healthcheck {
      name                = "kube-api"
      interval            = 2
      timeout             = 1
      unhealthy_threshold = 2
      healthy_threshold   = 2

      tcp_options {
        port = local.api_port
      }
    }
  }

  listener {
    name        = "http"
    port        = 80
    target_port = local.gateway_node_port
    protocol    = "tcp"

    external_address_spec {
      address    = yandex_vpc_address.api.external_ipv4_address[0].address
      ip_version = "ipv4"
    }
  }

  listener {
    name        = "https"
    port        = 443
    target_port = local.edge_port
    protocol    = "tcp"

    external_address_spec {
      address    = yandex_vpc_address.api.external_ipv4_address[0].address
      ip_version = "ipv4"
    }
  }
}
