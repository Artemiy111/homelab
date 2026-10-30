terraform {
  required_version = "~> 1.16"

  backend "s3" {
    endpoints                   = { s3 = "https://storage.yandexcloud.net" }
    bucket                      = "homelab-tfstate-b1g8d4t4aj6tj58ae7e4"
    key                         = "yc/nexus/terraform.tfstate"
    region                      = "ru-central1"
    profile                     = "yc-tfstate"
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_lockfile                = true
  }

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.243"
    }
  }
}

provider "yandex" {}

data "yandex_vpc_network" "cluster" {
  name = "k8s-vm"
}

data "yandex_vpc_subnet" "node" {
  for_each = {
    d = "k8s-vm-ru-central1-d"
    e = "k8s-vm-ru-central1-e"
  }

  name = each.value
}

data "yandex_vpc_security_group" "nodes" {
  name = "yc-nodes"
}

locals {
  cluster_name = "nexus"
  database     = "nexus"
  user         = "nexus"
  port         = 6432
}
