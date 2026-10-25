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

data "yandex_client_config" "current" {}

locals {
  bucket_name = "homelab-tfstate-${data.yandex_client_config.current.cloud_id}"
}
