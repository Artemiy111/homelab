terraform {
  required_version = "~> 1.16"

  backend "s3" {
    endpoints                   = { s3 = "https://storage.yandexcloud.net" }
    bucket                      = "homelab-tfstate-b1g8d4t4aj6tj58ae7e4"
    key                         = "yc/tls/terraform.tfstate"
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
      version = "~> 0.238"
    }
  }
}

provider "yandex" {}

data "yandex_dns_zone" "cluster" {
  name = "yc"
}

locals {
  zone   = "yc.clusters.biplane.casa"
  domain = "*.${local.zone}"
}
