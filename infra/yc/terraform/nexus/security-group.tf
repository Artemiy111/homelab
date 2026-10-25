resource "yandex_vpc_security_group" "postgres" {
  name       = "nexus-postgres"
  network_id = data.yandex_vpc_network.cluster.id

  ingress {
    protocol          = "TCP"
    port              = local.port
    security_group_id = data.yandex_vpc_security_group.nodes.id
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
