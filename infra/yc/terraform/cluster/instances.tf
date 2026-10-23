data "yandex_compute_image" "node" {
  family    = "ubuntu-2404-lts-oslogin"
  folder_id = "standard-images"
}

resource "yandex_compute_instance" "node" {
  for_each = local.nodes

  name        = "${local.cluster_name}-${each.key}"
  hostname    = "${local.cluster_name}-${each.key}"
  zone        = local.subnets[each.value.subnet].zone
  platform_id = "standard-v3"

  resources {
    cores         = 2
    memory        = 4
    core_fraction = 100
  }

  scheduling_policy {
    preemptible = false
  }

  boot_disk {
    initialize_params {
      name     = "${local.cluster_name}-${each.key}"
      image_id = data.yandex_compute_image.node.id
      type     = "network-ssd"
      size     = 10
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.node[each.value.subnet].id
    ip_address         = each.value.ip
    nat                = true
    security_group_ids = [yandex_vpc_security_group.node.id]
  }

  metadata = {
    enable-oslogin     = "true"
    serial-port-enable = "0"
  }

  labels = {
    cluster = local.cluster_name
  }

  allow_stopping_for_update = true

  lifecycle {
    ignore_changes = [boot_disk[0].initialize_params[0].image_id]
  }
}
