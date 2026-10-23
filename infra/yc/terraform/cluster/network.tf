resource "yandex_vpc_network" "cluster" {
  name        = "k8s-vm"
  description = "Сеть кластера ${local.cluster_name}"
}

resource "yandex_vpc_subnet" "node" {
  for_each = local.subnets

  name           = "k8s-vm-${each.value.zone}"
  description    = "Подсеть узлов кластера ${local.cluster_name} в зоне ${each.value.zone}"
  zone           = each.value.zone
  network_id     = yandex_vpc_network.cluster.id
  v4_cidr_blocks = [each.value.cidr]
}

resource "yandex_vpc_security_group" "node" {
  name       = "${local.cluster_name}-nodes"
  network_id = yandex_vpc_network.cluster.id

  ingress {
    description       = "kube-api от проверок доступности балансировщика"
    protocol          = "TCP"
    port              = local.api_port
    predefined_target = "loadbalancer_healthchecks"
  }

  ingress {
    description    = "kube-api от разрешённых сетей"
    protocol       = "TCP"
    port           = local.api_port
    v4_cidr_blocks = local.api_allowed_cidrs
  }

  ingress {
    description    = "SSH от разрешённых сетей"
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = local.ssh_allowed_cidrs
  }

  ingress {
    description       = "Трафик между узлами кластера"
    protocol          = "ANY"
    predefined_target = "self_security_group"
  }

  ingress {
    description    = "HTTP от балансировщика на NodePort"
    protocol       = "TCP"
    port           = local.gateway_node_port
    v4_cidr_blocks = local.http_allowed_cidrs
  }

  egress {
    description    = "Исходящий трафик"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
