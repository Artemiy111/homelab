terraform {
  required_version = "~> 1.16"

  backend "s3" {
    bucket = "terraform-state"
    key    = "casa/tailscale/terraform.tfstate"
    region = "us-east-1"

    endpoints = {
      s3 = "https://s3.biplane.casa"
    }

    use_path_style              = true
    use_lockfile                = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
  }

  required_providers {
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.29"
    }
  }
}

provider "tailscale" {}

locals {
  domain  = "biplane.casa"
  host_ip = "192.168.1.254"
}
