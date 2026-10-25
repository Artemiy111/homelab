resource "yandex_mdb_postgresql_cluster" "nexus" {
  name        = local.cluster_name
  environment = "PRODUCTION"
  network_id  = data.yandex_vpc_network.cluster.id

  config {
    version = "18"

    resources {
      resource_preset_id = "s3-c2-m8"
      disk_type_id       = "network-ssd"
      disk_size          = 20
    }

    backup_window_start {
      hours   = 22
      minutes = 0
    }

    backup_retain_period_days = 7

    connection_manager {
      enabled = true
    }
  }

  host {
    name      = "nexus-d"
    zone      = "ru-central1-d"
    subnet_id = data.yandex_vpc_subnet.node["d"].id
    priority  = 0
  }

  host {
    name      = "nexus-e"
    zone      = "ru-central1-e"
    subnet_id = data.yandex_vpc_subnet.node["e"].id
    priority  = 1
  }

  security_group_ids = [yandex_vpc_security_group.postgres.id]
}

resource "yandex_mdb_postgresql_user" "nexus" {
  cluster_id        = yandex_mdb_postgresql_cluster.nexus.id
  name              = local.user
  generate_password = true
  conn_limit        = 50

  user_connection_manager {}
}

resource "yandex_mdb_postgresql_database" "nexus" {
  cluster_id = yandex_mdb_postgresql_cluster.nexus.id
  name       = local.database
  owner      = yandex_mdb_postgresql_user.nexus.name
  lc_collate = "C"
  lc_type    = "C"

  extension {
    name = "pg_trgm"
  }
}
