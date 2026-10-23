terraform {
  required_version = "~> 1.16"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.238"
    }
  }
}

provider "yandex" {}

locals {
  cluster_name = "yc"
  lb_name      = "nlb-k8s-vm"
  region_id    = "ru-central1"
  api_port     = 6443

  parent_domain = "biplane.casa"
  dns_zone_name = "yc.clusters"
  dns_zone      = "${local.dns_zone_name}.${local.parent_domain}."
  api_fqdn      = "api.${local.dns_zone_name}.${local.parent_domain}"

  ssh_allowed_cidrs   = ["0.0.0.0/0"]
  api_allowed_cidrs   = ["0.0.0.0/0"]
  http_allowed_cidrs  = ["0.0.0.0/0"]
  https_allowed_cidrs = ["0.0.0.0/0"]
  gateway_node_port   = 30081
  edge_node_port      = 30443
  deletion_protection = false

  subnets = {
    d = { zone = "ru-central1-d", cidr = "10.133.0.0/24" }
    e = { zone = "ru-central1-e", cidr = "10.134.0.0/24" }
  }

  nodes = {
    d1 = { subnet = "d", ip = "10.133.0.11" }
    d2 = { subnet = "d", ip = "10.133.0.12" }
    e1 = { subnet = "e", ip = "10.134.0.11" }
  }
}
